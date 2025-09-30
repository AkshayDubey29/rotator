#!/bin/bash

# Troubleshoot Missing "up" Metric for Rotator
# Diagnoses why Prometheus/Grafana Agent is not scraping rotator

set -e

echo "🚨 Troubleshooting Missing 'up' Metric for Rotator"
echo "=================================================="
echo ""

# Configuration
NAMESPACE=${1:-"log-rotation"}
METRICS_PORT=${2:-9090}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Checking namespace: $NAMESPACE"
echo "🔍 Expected metrics port: $METRICS_PORT"
echo ""

# Step 1: Check if rotator service exists and is properly configured
check_service() {
    echo "1️⃣ Checking Rotator Service..."
    
    if ! kubectl get svc rotator -n $NAMESPACE &>/dev/null; then
        echo -e "${RED}❌ Rotator service NOT found in namespace $NAMESPACE${NC}"
        echo ""
        echo "Available services in $NAMESPACE:"
        kubectl get svc -n $NAMESPACE
        return 1
    fi
    
    echo -e "${GREEN}✅ Rotator service exists${NC}"
    
    # Check service configuration
    SERVICE_PORT=$(kubectl get svc rotator -n $NAMESPACE -o jsonpath="{.spec.ports[0].port}")
    SERVICE_TARGET_PORT=$(kubectl get svc rotator -n $NAMESPACE -o jsonpath="{.spec.ports[0].targetPort}")
    
    echo "   Service port: $SERVICE_PORT"
    echo "   Target port: $SERVICE_TARGET_PORT"
    
    if [[ "$SERVICE_PORT" != "$METRICS_PORT" ]]; then
        echo -e "${YELLOW}⚠️  Service port ($SERVICE_PORT) != expected port ($METRICS_PORT)${NC}"
    fi
    
    # Check service endpoints
    echo ""
    echo "   Service endpoints:"
    kubectl get endpoints rotator -n $NAMESPACE -o yaml | grep -A 10 "subsets:" || echo "   No endpoints found"
}

# Step 2: Check ServiceMonitor existence and configuration
check_servicemonitor() {
    echo ""
    echo "2️⃣ Checking ServiceMonitor..."
    
    if ! kubectl get servicemonitor rotator -n $NAMESPACE &>/dev/null; then
        echo -e "${RED}❌ ServiceMonitor NOT found in namespace $NAMESPACE${NC}"
        echo ""
        echo "Available ServiceMonitors in $NAMESPACE:"
        kubectl get servicemonitor -n $NAMESPACE 2>/dev/null || echo "   No ServiceMonitors found"
        echo ""
        echo "🔧 TO FIX: Deploy ServiceMonitor"
        echo "   kubectl apply -f production-servicemonitor.yaml"
        return 1
    fi
    
    echo -e "${GREEN}✅ ServiceMonitor exists${NC}"
    
    # Check ServiceMonitor configuration
    echo ""
    echo "   ServiceMonitor configuration:"
    kubectl get servicemonitor rotator -n $NAMESPACE -o yaml | grep -A 20 "spec:" | head -15
    
    # Check if path is configured
    SM_PATH=$(kubectl get servicemonitor rotator -n $NAMESPACE -o jsonpath="{.spec.endpoints[0].path}" 2>/dev/null)
    if [[ "$SM_PATH" == "/metrics" ]]; then
        echo -e "${GREEN}✅ ServiceMonitor has correct /metrics path${NC}"
    else
        echo -e "${RED}❌ ServiceMonitor missing /metrics path (found: '$SM_PATH')${NC}"
    fi
}

# Step 3: Check ServiceMonitor labels vs Grafana Agent selector
check_servicemonitor_labels() {
    echo ""
    echo "3️⃣ Checking ServiceMonitor Labels..."
    
    echo "   ServiceMonitor labels:"
    kubectl get servicemonitor rotator -n $NAMESPACE -o jsonpath="{.metadata.labels}" | jq . 2>/dev/null || kubectl get servicemonitor rotator -n $NAMESPACE -o jsonpath="{.metadata.labels}"
    
    echo ""
    echo "🔍 Grafana Agent Configuration Check:"
    echo "   Looking for Grafana Agent ConfigMaps..."
    
    # Check for common Grafana Agent ConfigMaps
    kubectl get cm --all-namespaces | grep -E "(grafana|alloy|agent)" | head -5
    
    echo ""
    echo "🔧 CRITICAL: Verify ServiceMonitor labels match Grafana Agent serviceMonitorSelector"
    echo "   1. Check your Grafana Agent config for serviceMonitorSelector"
    echo "   2. Add matching labels to ServiceMonitor metadata.labels"
    echo "   3. Common labels needed:"
    echo "      - release: <grafana-agent-release-name>"
    echo "      - prometheus: <prometheus-instance-name>"
    echo "      - monitoring: enabled"
}

# Step 4: Check if rotator pod is running and healthy
check_rotator_health() {
    echo ""
    echo "4️⃣ Checking Rotator Pod Health..."
    
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=rotator -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [[ -z "$POD_NAME" ]]; then
        echo -e "${RED}❌ No rotator pod found${NC}"
        return 1
    fi
    
    POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath="{.status.phase}")
    echo "   Pod: $POD_NAME"
    echo "   Status: $POD_STATUS"
    
    if [[ "$POD_STATUS" != "Running" ]]; then
        echo -e "${RED}❌ Pod not running${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Pod is running${NC}"
    
    # Check recent logs
    echo ""
    echo "   Recent logs (last 5 lines):"
    kubectl logs $POD_NAME -n $NAMESPACE --tail=5 | while read line; do
        echo "   $line"
    done
}

# Step 5: Test metrics endpoint accessibility
test_metrics_endpoint() {
    echo ""
    echo "5️⃣ Testing Metrics Endpoint Accessibility..."
    
    # Test via service (simulates Grafana Agent access)
    echo "   Testing via Service (simulates Grafana Agent scraping)..."
    
    # Create a test pod to check service accessibility
    echo "   Creating test pod to verify service connectivity..."
    
    kubectl run metrics-test --image=curlimages/curl:latest --rm -it --restart=Never -- \
        curl -s http://rotator.$NAMESPACE.svc.cluster.local:$METRICS_PORT/metrics | head -5 &
    
    TEST_PID=$!
    sleep 10
    kill $TEST_PID 2>/dev/null || true
    
    echo ""
    echo "   If the above fails, Grafana Agent cannot reach the metrics endpoint"
}

# Step 6: Check for network policies that might block scraping
check_network_policies() {
    echo ""
    echo "6️⃣ Checking Network Policies..."
    
    NETPOL_COUNT=$(kubectl get networkpolicy -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$NETPOL_COUNT" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Found $NETPOL_COUNT NetworkPolicy(ies) in $NAMESPACE${NC}"
        echo "   NetworkPolicies might be blocking Grafana Agent scraping"
        echo ""
        kubectl get networkpolicy -n $NAMESPACE
        echo ""
        echo "🔧 Verify NetworkPolicies allow ingress from Grafana Agent namespace"
    else
        echo -e "${GREEN}✅ No NetworkPolicies found (should not block scraping)${NC}"
    fi
}

# Step 7: Provide fix recommendations
provide_fix_recommendations() {
    echo ""
    echo "7️⃣ Fix Recommendations:"
    echo ""
    
    echo -e "${BLUE}🔧 Most Common Issues & Fixes:${NC}"
    echo ""
    
    echo "1. ServiceMonitor not created:"
    echo "   kubectl apply -f production-servicemonitor.yaml"
    echo ""
    
    echo "2. ServiceMonitor labels don't match Grafana Agent selector:"
    echo "   - Find Grafana Agent serviceMonitorSelector config"
    echo "   - Add matching labels to ServiceMonitor"
    echo "   - Example: kubectl label servicemonitor rotator -n $NAMESPACE prometheus=my-prometheus"
    echo ""
    
    echo "3. Wrong metrics port:"
    echo "   - Ensure service port matches container port"
    echo "   - Update Helm values: rotator.metrics.port=$METRICS_PORT"
    echo ""
    
    echo "4. Namespace selector in Grafana Agent:"
    echo "   - Verify Grafana Agent is configured to scrape $NAMESPACE"
    echo "   - Check namespaceSelector in Grafana Agent config"
    echo ""
    
    echo "5. ServiceMonitor missing /metrics path:"
    echo "   - Ensure ServiceMonitor has path: /metrics in endpoints"
    echo ""
    
    echo -e "${BLUE}📊 Verify Fix:${NC}"
    echo "After making changes, wait 30-60 seconds then query:"
    echo "   up{job=~\".*rotator.*\"}"
    echo ""
    echo "Should return 1 if scraping is successful"
}

# Main execution
main() {
    check_service
    check_servicemonitor
    check_servicemonitor_labels
    check_rotator_health
    test_metrics_endpoint
    check_network_policies
    provide_fix_recommendations
}

# Handle help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [namespace] [metrics_port]"
    echo ""
    echo "Troubleshoots missing 'up' metric for rotator (Prometheus/Grafana Agent not scraping)"
    echo ""
    echo "Arguments:"
    echo "  namespace       Kubernetes namespace (default: log-rotation)"
    echo "  metrics_port    Expected metrics port (default: 9090)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Check log-rotation namespace, port 9090"
    echo "  $0 log-rotation 9090       # Explicit namespace and port"
    echo "  $0 default 9102            # Check default namespace, port 9102"
    exit 0
fi

main
