#!/bin/bash

# Script to find the correct ServiceMonitor labels for Prometheus discovery
# This checks your working node-exporter to determine what labels rotator needs

echo "🔍 Finding Prometheus ServiceMonitor Labels"
echo "=========================================="

echo ""
echo "1️⃣ Checking for node-exporter ServiceMonitor (working reference)..."

# Find node-exporter ServiceMonitor
NODE_EXPORTER_SM=$(kubectl get servicemonitor --all-namespaces -l app.kubernetes.io/name=node-exporter -o name 2>/dev/null | head -1)

if [ -n "$NODE_EXPORTER_SM" ]; then
    NAMESPACE=$(echo $NODE_EXPORTER_SM | xargs kubectl get --no-headers -o custom-columns=":metadata.namespace" 2>/dev/null)
    NAME=$(echo $NODE_EXPORTER_SM | xargs kubectl get --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    
    echo "✅ Found: $NAME in namespace $NAMESPACE"
    echo ""
    echo "📋 Node-exporter ServiceMonitor labels:"
    kubectl get servicemonitor -n "$NAMESPACE" "$NAME" -o jsonpath='{.metadata.labels}' | jq . 2>/dev/null || kubectl get servicemonitor -n "$NAMESPACE" "$NAME" -o yaml | grep -A 10 "labels:"
    
    echo ""
    echo "🎯 COPY THESE EXACT LABELS to your rotator ServiceMonitor!"
    echo ""
else
    echo "❌ No node-exporter ServiceMonitor found with standard labels"
    echo ""
    
    # Look for any ServiceMonitor as backup
    echo "2️⃣ Searching for any ServiceMonitor as reference..."
    ALL_SM=$(kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | head -5)
    
    if [ -n "$ALL_SM" ]; then
        echo "📋 Found ServiceMonitors:"
        echo "$ALL_SM"
        echo ""
        echo "Pick one that works with your Prometheus and check its labels:"
        echo 'kubectl get servicemonitor -n <namespace> <name> -o yaml | grep -A 10 "labels:"'
    else
        echo "❌ No ServiceMonitors found at all"
    fi
fi

echo ""
echo "3️⃣ Checking Prometheus instances and their selectors..."

# Check Prometheus instances
PROM_INSTANCES=$(kubectl get prometheus --all-namespaces --no-headers 2>/dev/null)

if [ -n "$PROM_INSTANCES" ]; then
    echo "✅ Found Prometheus instances:"
    echo "$PROM_INSTANCES"
    echo ""
    
    echo "📋 ServiceMonitor selectors for each Prometheus:"
    kubectl get prometheus --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{": serviceMonitorSelector="}{.spec.serviceMonitorSelector}{"\n"}{end}' 2>/dev/null
    
    echo ""
    echo "🎯 Your ServiceMonitor labels MUST match one of these selectors!"
    echo ""
else
    echo "⚠️ No Prometheus CRDs found - you might not be using Prometheus Operator"
    
    # Look for Prometheus pods
    echo ""
    echo "4️⃣ Looking for Prometheus pods..."
    PROM_PODS=$(kubectl get pods --all-namespaces | grep prometheus | head -5)
    
    if [ -n "$PROM_PODS" ]; then
        echo "📋 Found Prometheus-related pods:"
        echo "$PROM_PODS"
        echo ""
        echo "Check your Prometheus configuration file for serviceMonitor discovery rules"
    else
        echo "❌ No Prometheus pods found"
    fi
fi

echo ""
echo "5️⃣ Recommendations based on common setups:"
echo ""

echo "🏷️ For kube-prometheus-stack:"
echo '  serviceMonitor:'
echo '    labels:'
echo '      prometheus: kube-prometheus'
echo '      release: kube-prometheus-stack'
echo ""

echo "🏷️ For Prometheus Operator:"
echo '  serviceMonitor:'
echo '    labels:'
echo '      prometheus: prometheus-operator' 
echo '      release: prometheus-operator'
echo ""

echo "🏷️ For Rancher Monitoring:"
echo '  serviceMonitor:'
echo '    labels:'
echo '      source: rancher-monitoring'
echo '      prometheus: rancher-monitoring-prometheus'
echo ""

echo "🏷️ For custom Prometheus:"
echo '  serviceMonitor:'
echo '    labels:'
echo '      monitoring: enabled'
echo '      # Or whatever labels your Prometheus uses'
echo ""

echo ""
echo "6️⃣ Testing steps after adding labels:"
echo ""
echo "1. Update your values.yaml with the matching labels"
echo "2. Apply: helm upgrade rotator ./helm/rotator -f your-values.yaml"
echo "3. Check Prometheus targets: kubectl port-forward svc/prometheus 9090:9090"
echo "4. Visit: http://localhost:9090/targets (look for rotator)"
echo "5. Query in Prometheus: up{job=~\".*rotator.*\"}"
echo ""

echo "✅ Script completed!"
