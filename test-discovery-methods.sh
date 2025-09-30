#!/bin/bash

# Test Both Discovery Methods for Grafana Agent Integration
# Checks annotation-based vs ServiceMonitor-based discovery

echo "🔍 Testing Discovery Methods for Rotator"
echo "========================================"
echo ""

NAMESPACE="log-rotation"

# Test 1: Check if mimir-rls uses annotations (to understand the pattern)
echo "1️⃣ Analyzing mimir-rls discovery pattern..."
echo ""

if kubectl get svc mimir-rls &>/dev/null; then
    echo "   mimir-rls Service annotations:"
    kubectl get svc mimir-rls -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || kubectl get svc mimir-rls -o jsonpath='{.metadata.annotations}'
    echo ""
    
    echo "   mimir-rls ServiceMonitor (if exists):"
    if kubectl get servicemonitor mimir-rls &>/dev/null; then
        echo "   ✅ Has ServiceMonitor"
    else
        echo "   ❌ No ServiceMonitor - likely uses annotation discovery"
    fi
else
    echo "   mimir-rls not found - checking other working services"
fi

echo ""

# Test 2: Check current rotator configuration
echo "2️⃣ Current rotator configuration..."
echo ""

echo "   Rotator Service annotations:"
kubectl get svc rotator -n $NAMESPACE -o jsonpath='{.metadata.annotations}' 2>/dev/null | jq . 2>/dev/null || echo "   No annotations found"

echo ""
echo "   Rotator ServiceMonitor:"
if kubectl get servicemonitor rotator -n $NAMESPACE &>/dev/null; then
    echo "   ✅ ServiceMonitor exists"
else
    echo "   ❌ ServiceMonitor missing"
fi

echo ""

# Test 3: Apply annotation-based discovery
echo "3️⃣ Testing annotation-based discovery..."
echo ""

echo "   Adding Prometheus annotations to rotator service..."
kubectl annotate service rotator -n $NAMESPACE \
  prometheus.io/scrape=true \
  prometheus.io/path=/metrics \
  prometheus.io/port=9090 \
  --overwrite

echo "   ✅ Annotations added"

echo ""
echo "   Updated Service annotations:"
kubectl get svc rotator -n $NAMESPACE -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || kubectl get svc rotator -n $NAMESPACE -o jsonpath='{.metadata.annotations}'

echo ""

# Test 4: Check Grafana Agent logs for discovery
echo "4️⃣ Checking Grafana Agent discovery..."
echo ""

echo "   Looking for Grafana Agent pods..."
kubectl get pods --all-namespaces -l app=alloy 2>/dev/null | head -5 || echo "   No alloy pods found"
kubectl get pods --all-namespaces -l app.kubernetes.io/name=alloy 2>/dev/null | head -5 || echo "   No alloy pods with k8s labels found"

echo ""

# Test 5: Verify both methods are configured
echo "5️⃣ Verification Summary..."
echo ""

echo "   📊 Discovery Methods Status:"
echo ""

# Check annotations
SCRAPE_ANNOTATION=$(kubectl get svc rotator -n $NAMESPACE -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' 2>/dev/null)
if [[ "$SCRAPE_ANNOTATION" == "true" ]]; then
    echo "   ✅ Annotation-based discovery: ENABLED"
    echo "      - prometheus.io/scrape: true"
    echo "      - prometheus.io/path: /metrics"
    echo "      - prometheus.io/port: 9090"
else
    echo "   ❌ Annotation-based discovery: DISABLED"
fi

# Check ServiceMonitor
if kubectl get servicemonitor rotator -n $NAMESPACE &>/dev/null; then
    echo "   ✅ ServiceMonitor-based discovery: ENABLED"
else
    echo "   ❌ ServiceMonitor-based discovery: DISABLED"
fi

echo ""

# Test 6: Wait and check if metrics appear
echo "6️⃣ Testing metric discovery (wait 60 seconds)..."
echo ""

echo "   Waiting 60 seconds for Grafana Agent to discover new configuration..."
echo "   (Grafana Agent typically discovers services every 30-60 seconds)"

for i in {60..1}; do
    printf "\r   Waiting: %d seconds remaining..." $i
    sleep 1
done
printf "\r   ✅ Wait complete                    \n"

echo ""
echo "🎯 Next Steps:"
echo ""
echo "1. Check if up{job=~\".*rotator.*\"} now returns 1 in Mimir"
echo "2. Query rotator_scan_cycles_total to verify metrics"
echo "3. Check Grafana Agent logs for any scrape errors:"
echo "   kubectl logs -l app=alloy --tail=20"
echo ""
echo "📊 Test Queries for Mimir:"
echo "   up{job=~\".*rotator.*\"}"
echo "   rotator_scan_cycles_total"
echo "   rotator_files_discovered"
