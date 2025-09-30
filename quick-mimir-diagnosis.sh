#!/bin/bash

# Quick Mimir Integration Diagnosis for Production
# Focuses on the most common issues preventing 'up' metrics

echo "🚨 Quick Mimir Integration Diagnosis"
echo "===================================="
echo ""

NAMESPACE="log-rotation"

echo "🔍 Checking rotator deployment in $NAMESPACE namespace..."
echo ""

# 1. Check if rotator service exists
echo "1️⃣ Service Check:"
if kubectl get svc rotator -n $NAMESPACE &>/dev/null; then
    echo "✅ Service exists"
    kubectl get svc rotator -n $NAMESPACE
else
    echo "❌ Service missing"
    exit 1
fi

echo ""

# 2. Check if ServiceMonitor exists  
echo "2️⃣ ServiceMonitor Check:"
if kubectl get servicemonitor rotator -n $NAMESPACE &>/dev/null; then
    echo "✅ ServiceMonitor exists"
    
    # Check critical ServiceMonitor configuration
    echo "   Checking configuration..."
    
    # Check if /metrics path is configured
    PATH_CHECK=$(kubectl get servicemonitor rotator -n $NAMESPACE -o jsonpath="{.spec.endpoints[0].path}" 2>/dev/null)
    if [[ "$PATH_CHECK" == "/metrics" ]]; then
        echo "✅ Path: /metrics configured"
    else
        echo "❌ Missing /metrics path (found: '$PATH_CHECK')"
    fi
    
    # Show current labels
    echo "   ServiceMonitor labels:"
    kubectl get servicemonitor rotator -n $NAMESPACE -o jsonpath="{.metadata.labels}" | jq . 2>/dev/null || kubectl get servicemonitor rotator -n $NAMESPACE -o jsonpath="{.metadata.labels}"
    
else
    echo "❌ ServiceMonitor missing - THIS IS LIKELY THE ISSUE!"
    echo ""
    echo "🔧 FIX: Create ServiceMonitor"
    echo "kubectl apply -f production-servicemonitor.yaml"
    exit 1
fi

echo ""

# 3. Check rotator pod health
echo "3️⃣ Pod Health:"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=rotator -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [[ -n "$POD_NAME" ]]; then
    POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath="{.status.phase}")
    echo "✅ Pod: $POD_NAME ($POD_STATUS)"
    
    if [[ "$POD_STATUS" == "Running" ]]; then
        echo "✅ Pod is healthy"
    else
        echo "❌ Pod not running"
    fi
else
    echo "❌ No rotator pod found"
fi

echo ""

# 4. Check Grafana Agent ConfigMaps
echo "4️⃣ Grafana Agent Config:"
echo "   Looking for Grafana Agent ConfigMaps..."
kubectl get cm --all-namespaces | grep -E "(grafana|alloy)" | head -3

echo ""

# 5. Most likely fixes
echo "🎯 MOST LIKELY ISSUES:"
echo ""
echo "1. ServiceMonitor labels don't match Grafana Agent selector"
echo "   Solution: Add correct labels to ServiceMonitor"
echo ""
echo "2. ServiceMonitor not in correct namespace" 
echo "   Solution: Ensure ServiceMonitor is in $NAMESPACE"
echo ""
echo "3. Grafana Agent not configured to scrape $NAMESPACE"
echo "   Solution: Check Grafana Agent namespaceSelector config"
echo ""

echo "🔍 NEXT STEPS:"
echo "1. Run: ./troubleshoot-up-metric.sh $NAMESPACE 9090"
echo "2. Check Grafana Agent logs for scrape errors"
echo "3. Verify ServiceMonitor labels match your Grafana Agent config"
echo ""

echo "📊 TEST QUERY (should return 1 when fixed):"
echo "up{job=~\".*rotator.*\"}"
