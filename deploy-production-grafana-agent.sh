#!/bin/bash

# Production Deployment Script for Grafana Agent Environment
# Based on your cluster configuration analysis

set -e

echo "🚀 Deploying Rotator for Grafana Agent + Mimir Environment"
echo "========================================================="

# Configuration
NAMESPACE="log-rotation"
RELEASE_NAME="rotator"
IMAGE_REGISTRY="your-registry/rotator"  # Update this
IMAGE_TAG="v1.1.0"

echo "📊 Environment Configuration:"
echo "  Cluster: Grafana Agent + Mimir"
echo "  Namespace: $NAMESPACE"
echo "  Release: $RELEASE_NAME"
echo "  Port: 9090 (matches your pushgateway pattern)"
echo ""

# Step 1: Check current deployment
echo "1️⃣ Checking current deployment..."
if kubectl get svc rotator -n $NAMESPACE &> /dev/null; then
    echo "✅ Rotator service exists"
    kubectl get svc rotator -n $NAMESPACE
else
    echo "❌ Rotator service not found"
fi

if kubectl get servicemonitor rotator -n $NAMESPACE &> /dev/null; then
    echo "✅ ServiceMonitor exists"
    kubectl get servicemonitor rotator -n $NAMESPACE
else
    echo "❌ ServiceMonitor missing - this is likely the issue!"
fi

echo ""

# Step 2: Deploy with correct configuration
echo "2️⃣ Deploying rotator with Grafana Agent configuration..."

# Create deployment command
DEPLOY_CMD="helm upgrade --install $RELEASE_NAME ./helm/rotator \\
  --namespace $NAMESPACE \\
  --create-namespace \\
  -f helm/rotator/production-values.yaml \\
  --set rotator.image.repository=$IMAGE_REGISTRY \\
  --set rotator.image.tag=$IMAGE_TAG \\
  --set rotator.metrics.port=9090 \\
  --set serviceMonitor.enabled=true \\
  --wait"

echo "📦 Deployment command:"
echo "$DEPLOY_CMD"
echo ""

# Ask for confirmation
read -p "🔧 Update IMAGE_REGISTRY above, then press Enter to deploy (or Ctrl+C to abort): "

# Deploy
echo "🚀 Deploying..."
helm upgrade --install $RELEASE_NAME ./helm/rotator \
  --namespace $NAMESPACE \
  --create-namespace \
  -f helm/rotator/production-values.yaml \
  --set rotator.image.repository=$IMAGE_REGISTRY \
  --set rotator.image.tag=$IMAGE_TAG \
  --set rotator.metrics.port=9090 \
  --set serviceMonitor.enabled=true \
  --wait

echo ""

# Step 3: Verify deployment
echo "3️⃣ Verifying deployment..."

echo "📋 Checking pods..."
kubectl get pods -n $NAMESPACE -l app=rotator

echo ""
echo "📋 Checking service..."
kubectl get svc rotator -n $NAMESPACE

echo ""
echo "📋 Checking ServiceMonitor..."
kubectl get servicemonitor rotator -n $NAMESPACE -o yaml | grep -A 20 "spec:"

echo ""

# Step 4: Test metrics endpoint
echo "4️⃣ Testing metrics endpoint..."
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=rotator -o jsonpath="{.items[0].metadata.name}")
echo "   Using pod: $POD_NAME"

echo "   Testing internal metrics..."
METRICS_COUNT=$(kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- http://localhost:9090/metrics 2>/dev/null | grep -c "rotator_" || echo "0")
echo "   ✅ Found $METRICS_COUNT rotator metrics"

if [ "$METRICS_COUNT" -gt 0 ]; then
    echo "   Sample metrics:"
    kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- http://localhost:9090/metrics 2>/dev/null | grep "rotator_" | head -3
fi

echo ""

# Step 5: Check Grafana Agent integration
echo "5️⃣ Checking Grafana Agent integration..."

echo "📋 Grafana Agent ConfigMaps:"
kubectl get cm -n monitoring | grep -E "(grafana|alloy)" || echo "   No Grafana Agent ConfigMaps found in monitoring namespace"

echo ""
echo "📋 ServiceMonitor discovery test:"
echo "   ServiceMonitor should be discovered by Grafana Agent automatically"
echo "   Check Grafana Agent logs for scrape target discovery:"
echo "   kubectl logs -n monitoring <grafana-agent-pod>"

echo ""

# Step 6: Next steps
echo "6️⃣ Next steps for Mimir verification:"
echo ""
echo "🔍 1. Verify in Mimir/Grafana:"
echo "   - Check if rotator targets appear in Grafana Agent"
echo "   - Query in Mimir: up{job=~\".*rotator.*\"}"
echo "   - Query: rotator_scan_cycles_total"
echo "   - Query: rotator_files_discovered"
echo ""
echo "🔧 2. If metrics still don't appear:"
echo "   a) Check Grafana Agent configuration:"
echo "      kubectl get cm mimir-monitoring-alloy -o yaml"
echo "   b) Check Grafana Agent logs:"
echo "      kubectl logs -n monitoring -l app=grafana-agent"
echo "   c) Verify ServiceMonitor selector in Grafana Agent config"
echo ""
echo "📊 3. Production monitoring queries:"
echo "   - Health: up{job=~\".*rotator.*\"}"
echo "   - Activity: rate(rotator_scan_cycles_total[5m])"
echo "   - Files: rotator_files_discovered"
echo "   - Rotations: rate(rotator_rotations_total[5m])"
echo "   - Errors: rate(rotator_errors_total[5m])"
echo ""

echo "✅ Deployment completed!"
echo ""
echo "🎯 Key changes made:"
echo "   ✅ Port 9090 (matches your environment)"
echo "   ✅ ServiceMonitor enabled with proper labels"
echo "   ✅ Namespace: log-rotation"
echo "   ✅ Standard Kubernetes labels for Grafana Agent discovery"
