#!/bin/bash

# Complete Mimir Integration Fix Script
# This script deploys rotator with all necessary configurations for Mimir

set -e

echo "🔧 Fixing Rotator Mimir Integration"
echo "=================================="

# Configuration
NAMESPACE=${ROTATOR_NAMESPACE:-default}
RELEASE_NAME=${ROTATOR_RELEASE:-rotator}

echo "📊 Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Release: $RELEASE_NAME"
echo ""

# Step 1: Find Prometheus labels (if possible)
echo "1️⃣ Checking for existing Prometheus ServiceMonitor labels..."

NODE_EXPORTER_LABELS=$(kubectl get servicemonitor --all-namespaces -l app.kubernetes.io/name=node-exporter -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null || echo "{}")

if [ "$NODE_EXPORTER_LABELS" != "{}" ]; then
    echo "✅ Found node-exporter ServiceMonitor labels:"
    echo "$NODE_EXPORTER_LABELS" | jq . 2>/dev/null || echo "$NODE_EXPORTER_LABELS"
    echo ""
    echo "🎯 You should copy these exact labels to your values file!"
    echo ""
else
    echo "⚠️  No node-exporter ServiceMonitor found"
    echo "   You'll need to find the correct labels manually"
    echo ""
fi

# Step 2: Deploy with updated configuration
echo "2️⃣ Deploying rotator with ServiceMonitor enabled..."

# Create temporary values file with fixes
cat > /tmp/rotator-mimir-fix.yaml << EOF
# Enable ServiceMonitor (was disabled - this is the main issue!)
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
  honorLabels: false
  labels:
    # TODO: Add your Prometheus labels here
    # Copy from node-exporter ServiceMonitor labels shown above
    # Example:
    # prometheus: kube-prometheus
    # release: kube-prometheus-stack

# Enhanced service configuration
service:
  labels: {}

# Ensure we're using updated image with metrics fixes
rotator:
  image:
    repository: localhost/rotator
    tag: metrics-v2
    pullPolicy: IfNotPresent

# Production security context
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  fsGroup: 65534
EOF

echo "📦 Upgrading Helm release..."
helm upgrade $RELEASE_NAME ./helm/rotator \
  --namespace $NAMESPACE \
  -f /tmp/rotator-mimir-fix.yaml \
  --wait

echo ""
echo "3️⃣ Verifying deployment..."

# Check if ServiceMonitor was created
echo "📋 Checking ServiceMonitor creation..."
if kubectl get servicemonitor -n $NAMESPACE rotator &> /dev/null; then
    echo "✅ ServiceMonitor created successfully"
    kubectl get servicemonitor -n $NAMESPACE rotator -o yaml | grep -A 10 "labels:"
else
    echo "❌ ServiceMonitor not created - check Prometheus Operator installation"
fi

echo ""
echo "📋 Checking Service endpoints..."
kubectl get endpoints -n $NAMESPACE rotator

echo ""
echo "📋 Testing metrics endpoint..."
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=rotator -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- http://localhost:9102/metrics | head -3

echo ""
echo "4️⃣ Next steps for Mimir integration:"
echo ""
echo "🎯 Critical: Update ServiceMonitor labels"
echo "   1. Find your Prometheus ServiceMonitor selector:"
echo "      kubectl get prometheus --all-namespaces -o yaml | grep -A 5 serviceMonitorSelector"
echo ""
echo "   2. Update values file with matching labels:"
echo "      serviceMonitor:"
echo "        labels:"
echo "          prometheus: <your-prometheus-label>"
echo "          release: <your-release-label>"
echo ""
echo "   3. Re-run deployment:"
echo "      helm upgrade $RELEASE_NAME ./helm/rotator -f your-values.yaml"
echo ""
echo "📊 Verification in production:"
echo "   1. Check Prometheus targets: kubectl port-forward svc/prometheus 9090:9090"
echo "   2. Visit: http://localhost:9090/targets (look for rotator)"
echo "   3. Query in Mimir: up{job=~\".*rotator.*\"}"
echo ""

# Cleanup
rm -f /tmp/rotator-mimir-fix.yaml

echo "✅ Deployment completed with ServiceMonitor enabled!"
echo ""
echo "⚠️  Remember: You still need to add the correct Prometheus labels"
echo "   to make ServiceMonitor discoverable by your Prometheus instance."
