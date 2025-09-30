#!/bin/bash

# Mimir Integration Troubleshooting Script for Rotator
# This script helps diagnose why rotator metrics aren't appearing in Mimir

set -e

echo "🔧 Rotator Mimir Integration Troubleshooting"
echo "============================================="

# Configuration
NAMESPACE=${ROTATOR_NAMESPACE:-default}
SERVICE_NAME=${ROTATOR_SERVICE:-rotator}
PORT=${ROTATOR_PORT:-9102}

echo "📊 Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Service: $SERVICE_NAME"
echo "  Port: $PORT"
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl not found. Please ensure kubectl is installed and configured."
        exit 1
    fi
}

# Function to check rotator deployment
check_rotator_deployment() {
    echo "1️⃣ Checking Rotator Deployment..."
    
    # Check DaemonSet
    if kubectl get daemonset -n $NAMESPACE rotator &> /dev/null; then
        echo "✅ Rotator DaemonSet exists"
        kubectl get daemonset -n $NAMESPACE rotator -o wide
        
        # Check pod status
        READY_PODS=$(kubectl get pods -n $NAMESPACE -l app=rotator --no-headers | grep "1/1" | wc -l)
        TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app=rotator --no-headers | wc -l)
        echo "   Pods Ready: $READY_PODS/$TOTAL_PODS"
        
        if [ "$READY_PODS" -eq 0 ]; then
            echo "❌ No ready rotator pods found!"
            kubectl describe pods -n $NAMESPACE -l app=rotator
            exit 1
        fi
    else
        echo "❌ Rotator DaemonSet not found in namespace $NAMESPACE"
        exit 1
    fi
    echo ""
}

# Function to check service configuration
check_service() {
    echo "2️⃣ Checking Service Configuration..."
    
    if kubectl get service -n $NAMESPACE $SERVICE_NAME &> /dev/null; then
        echo "✅ Service exists"
        kubectl get service -n $NAMESPACE $SERVICE_NAME -o yaml
        
        # Check endpoints
        echo ""
        echo "📋 Service Endpoints:"
        kubectl get endpoints -n $NAMESPACE $SERVICE_NAME -o yaml
        
        ENDPOINT_COUNT=$(kubectl get endpoints -n $NAMESPACE $SERVICE_NAME -o jsonpath='{.subsets[0].addresses}' | jq length 2>/dev/null || echo "0")
        echo "   Endpoint Count: $ENDPOINT_COUNT"
        
        if [ "$ENDPOINT_COUNT" = "0" ] || [ "$ENDPOINT_COUNT" = "null" ]; then
            echo "⚠️  No service endpoints found - check pod selector labels"
        fi
    else
        echo "❌ Service $SERVICE_NAME not found in namespace $NAMESPACE"
        exit 1
    fi
    echo ""
}

# Function to test metrics endpoint
test_metrics_direct() {
    echo "3️⃣ Testing Metrics Endpoint Directly..."
    
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=rotator -o jsonpath="{.items[0].metadata.name}")
    echo "   Using pod: $POD_NAME"
    
    # Test metrics endpoint inside pod
    echo "   Testing metrics endpoint inside pod..."
    METRICS_TEST=$(kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- http://localhost:$PORT/metrics 2>/dev/null | grep -c "rotator_" || echo "0")
    echo "   Metrics found inside pod: $METRICS_TEST"
    
    if [ "$METRICS_TEST" = "0" ]; then
        echo "❌ No metrics found inside pod - application issue"
        kubectl logs -n $NAMESPACE $POD_NAME --tail=20
        exit 1
    else
        echo "✅ Metrics accessible inside pod"
    fi
    
    # Test via service
    echo "   Testing via service from within cluster..."
    kubectl run metrics-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
        curl -s --max-time 10 http://$SERVICE_NAME.$NAMESPACE:$PORT/metrics | head -5 || true
    
    echo ""
}

# Function to check ServiceMonitor
check_servicemonitor() {
    echo "4️⃣ Checking ServiceMonitor Configuration..."
    
    if kubectl get servicemonitor -n $NAMESPACE $SERVICE_NAME &> /dev/null; then
        echo "✅ ServiceMonitor exists"
        kubectl get servicemonitor -n $NAMESPACE $SERVICE_NAME -o yaml
        
        # Check if ServiceMonitor has proper labels
        echo ""
        echo "📋 ServiceMonitor Labels:"
        kubectl get servicemonitor -n $NAMESPACE $SERVICE_NAME -o jsonpath='{.metadata.labels}' | jq . 2>/dev/null || echo "No labels found"
        
    else
        echo "❌ ServiceMonitor not found. Creating basic ServiceMonitor..."
        cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    app: $SERVICE_NAME
spec:
  selector:
    matchLabels:
      app: $SERVICE_NAME
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
EOF
        echo "✅ Basic ServiceMonitor created"
    fi
    echo ""
}

# Function to find Prometheus instance
find_prometheus() {
    echo "5️⃣ Finding Prometheus Instance..."
    
    # Look for Prometheus pods
    PROM_PODS=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=prometheus -o wide 2>/dev/null || true)
    if [ ! -z "$PROM_PODS" ]; then
        echo "✅ Found Prometheus pods:"
        echo "$PROM_PODS"
        
        PROM_NAMESPACE=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "")
        PROM_POD=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ ! -z "$PROM_NAMESPACE" ] && [ ! -z "$PROM_POD" ]; then
            echo "   Using: $PROM_POD in namespace $PROM_NAMESPACE"
            
            # Check Prometheus configuration
            echo ""
            echo "📋 Checking Prometheus ServiceMonitor Selection..."
            kubectl exec -n $PROM_NAMESPACE $PROM_POD -- wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets[] | select(.labels.job | contains("rotator"))' 2>/dev/null || echo "No rotator targets found in Prometheus"
        fi
    else
        echo "⚠️  No Prometheus pods found with standard labels"
        
        # Look for alternative Prometheus installations
        echo "   Searching for other Prometheus installations..."
        kubectl get pods --all-namespaces | grep prometheus || echo "   No pods with 'prometheus' in name found"
    fi
    echo ""
}

# Function to check Prometheus Operator configuration
check_prometheus_operator() {
    echo "6️⃣ Checking Prometheus Operator Configuration..."
    
    # Check if Prometheus Operator is installed
    if kubectl get crd prometheuses.monitoring.coreos.com &> /dev/null; then
        echo "✅ Prometheus Operator CRDs found"
        
        # Check Prometheus resources
        PROMETHEUS_INSTANCES=$(kubectl get prometheus --all-namespaces 2>/dev/null || true)
        if [ ! -z "$PROMETHEUS_INSTANCES" ]; then
            echo "✅ Prometheus instances found:"
            echo "$PROMETHEUS_INSTANCES"
            
            # Check serviceMonitorSelector for each Prometheus instance
            echo ""
            echo "📋 ServiceMonitor Selectors:"
            kubectl get prometheus --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{": "}{.spec.serviceMonitorSelector}{"\n"}{end}' 2>/dev/null || echo "Could not retrieve selectors"
            
        else
            echo "⚠️  No Prometheus instances found"
        fi
    else
        echo "⚠️  Prometheus Operator not found (CRDs missing)"
        echo "   You may be using a different Prometheus setup"
    fi
    echo ""
}

# Function to provide specific troubleshooting steps
provide_troubleshooting_steps() {
    echo "7️⃣ Troubleshooting Steps Based on Your Setup..."
    echo ""
    
    echo "🔍 Since node-exporter is working, check these common issues:"
    echo ""
    
    echo "📌 A. ServiceMonitor Label Matching:"
    echo "   Your Prometheus might require specific labels on ServiceMonitors."
    echo "   Check your node-exporter ServiceMonitor labels:"
    echo "   kubectl get servicemonitor --all-namespaces -l app.kubernetes.io/name=node-exporter -o yaml"
    echo ""
    echo "   Then add matching labels to rotator ServiceMonitor in values.yaml:"
    echo "   serviceMonitor:"
    echo "     labels:"
    echo "       prometheus: kube-prometheus"
    echo "       release: prometheus-operator"
    echo ""
    
    echo "📌 B. Namespace Selection:"
    echo "   Your Prometheus might only scrape specific namespaces."
    echo "   Check Prometheus serviceMonitorNamespaceSelector:"
    echo "   kubectl get prometheus --all-namespaces -o yaml | grep -A 5 serviceMonitorNamespaceSelector"
    echo ""
    
    echo "📌 C. Network Policies:"
    echo "   Check if network policies block Prometheus → Rotator communication:"
    echo "   kubectl get networkpolicy --all-namespaces"
    echo ""
    
    echo "📌 D. Service Discovery:"
    echo "   Verify Prometheus can discover the rotator service:"
    echo "   # Port-forward to Prometheus and check targets"
    echo "   kubectl port-forward -n <prometheus-namespace> svc/prometheus 9090:9090"
    echo "   # Visit http://localhost:9090/targets and look for rotator"
    echo ""
    
    echo "📌 E. Mimir Remote Write:"
    echo "   Ensure Prometheus is successfully writing to Mimir:"
    echo "   # Check Prometheus logs for remote write errors"
    echo "   kubectl logs -n <prometheus-namespace> <prometheus-pod> | grep -i mimir"
    echo ""
}

# Function to generate a production-ready ServiceMonitor
generate_production_servicemonitor() {
    echo "8️⃣ Generating Production-Ready ServiceMonitor..."
    echo ""
    
    echo "📄 Copy this ServiceMonitor configuration and adapt labels to match your environment:"
    echo ""
    cat <<EOF
# Save as: rotator-servicemonitor.yaml
# Adapt labels to match your Prometheus serviceMonitorSelector
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rotator
  namespace: $NAMESPACE
  labels:
    app: rotator
    # ADD LABELS THAT MATCH YOUR PROMETHEUS SETUP:
    # prometheus: kube-prometheus           # Common for kube-prometheus-stack
    # release: prometheus-operator          # Common for Helm releases
    # monitoring: enabled                   # Custom label example
spec:
  selector:
    matchLabels:
      app: rotator
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
      scrapeTimeout: 10s
      honorLabels: false
  # Uncomment if Prometheus only scrapes specific namespaces:
  # namespaceSelector:
  #   matchNames:
  #   - $NAMESPACE
EOF
    echo ""
    echo "Apply with: kubectl apply -f rotator-servicemonitor.yaml"
    echo ""
}

# Function to show sample queries for verification
show_verification_queries() {
    echo "9️⃣ Verification Queries for Mimir..."
    echo ""
    
    echo "🔍 Once metrics appear in Mimir, use these queries to verify:"
    echo ""
    echo "# Basic health check"
    echo "up{job=~\".*rotator.*\"}"
    echo ""
    echo "# Scan activity (should increment every 30s)"
    echo "rate(rotator_scan_cycles_total[5m])"
    echo ""
    echo "# Current files being monitored"
    echo "rotator_files_discovered"
    echo ""
    echo "# Policy overrides being applied"
    echo "rate(rotator_overrides_applied_total[5m])"
    echo ""
    echo "# Error rate monitoring"
    echo "rate(rotator_errors_total[5m])"
    echo ""
}

# Main execution
main() {
    check_kubectl
    check_rotator_deployment
    check_service
    test_metrics_direct
    check_servicemonitor
    find_prometheus
    check_prometheus_operator
    provide_troubleshooting_steps
    generate_production_servicemonitor
    show_verification_queries
    
    echo "✅ Troubleshooting analysis completed!"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Compare rotator ServiceMonitor labels with working node-exporter"
    echo "   2. Update ServiceMonitor labels to match your Prometheus selector"
    echo "   3. Verify network connectivity between Prometheus and rotator"
    echo "   4. Check Prometheus targets page for rotator endpoint"
    echo "   5. Monitor Prometheus logs for scrape errors"
    echo "   6. Verify Mimir remote write configuration"
}

# Run the script
main "$@"
