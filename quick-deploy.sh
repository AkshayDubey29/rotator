#!/bin/bash
set -euo pipefail

# Rotator Log Rotation - Quick Deployment Script
# Usage: ./quick-deploy.sh [REGISTRY] [TAG]

REGISTRY=${1:-"your-registry"}
TAG=${2:-"v1.0.0"}
NAMESPACE="log-rotation"

echo "🚀 Starting Rotator Deployment"
echo "Registry: ${REGISTRY}"
echo "Tag: ${TAG}"
echo "Namespace: ${NAMESPACE}"

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ Helm is required but not installed."; exit 1; }

# Verify kubectl connection
kubectl cluster-info >/dev/null 2>&1 || { echo "❌ kubectl is not connected to a cluster"; exit 1; }

echo "✅ Prerequisites check passed"

# Build and push image
echo "🔨 Building container image..."
cd rotator
docker build -t ${REGISTRY}/rotator:${TAG} -f Dockerfile .

echo "📤 Pushing image to registry..."
docker push ${REGISTRY}/rotator:${TAG}

# Prepare cluster
echo "🏗️  Preparing cluster..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create log directories on nodes
echo "📁 Setting up log directories..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: prepare-log-dirs
  namespace: ${NAMESPACE}
spec:
  template:
    spec:
      hostPID: true
      containers:
      - name: prepare
        image: alpine
        command: ["/bin/sh", "-c"]
        args:
        - |
          mkdir -p /host/pang/logs
          chown 65534:65534 /host/pang/logs
          chmod 755 /host/pang/logs
          echo "Log directories prepared"
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-root
          mountPath: /host
      volumes:
      - name: host-root
        hostPath:
          path: /
      restartPolicy: Never
EOF

# Wait for job completion
kubectl wait --for=condition=complete job/prepare-log-dirs -n ${NAMESPACE} --timeout=60s
kubectl delete job prepare-log-dirs -n ${NAMESPACE}

# Deploy with Helm
echo "⚡ Deploying Rotator with Helm..."
cd ../helm/rotator

helm upgrade --install rotator . \
  --namespace ${NAMESPACE} \
  --set rotator.image.repository=${REGISTRY}/rotator \
  --set rotator.image.tag=${TAG} \
  --set serviceMonitor.enabled=false \
  --set priorityClass.create=false \
  --wait --timeout=300s

echo "✅ Rotator deployed successfully!"

# Verify deployment
echo "🔍 Verifying deployment..."
kubectl get pods -n ${NAMESPACE} -l app=rotator
kubectl get daemonset -n ${NAMESPACE}

# Show useful commands
echo ""
echo "🎉 Deployment Complete!"
echo ""
echo "📊 Monitor your deployment:"
echo "  kubectl logs -n ${NAMESPACE} -l app=rotator -f"
echo "  kubectl get pods -n ${NAMESPACE} -l app=rotator"
echo ""
echo "🔍 Access metrics:"
echo "  kubectl port-forward -n ${NAMESPACE} daemonset/rotator 9102:9102"
echo "  curl http://localhost:9102/metrics"
echo ""
echo "🧪 Deploy demo applications:"
echo "  kubectl create ns payments checkout shipping"
echo "  kubectl apply -n payments -f ../../hack/log-writer-daemonset.yaml"
echo "  kubectl apply -n checkout -f ../../hack/log-writer-daemonset.yaml"
echo "  kubectl apply -n shipping -f ../../hack/log-writer-daemonset.yaml"
echo ""
echo "🗑️  Clean up:"
echo "  helm uninstall rotator -n ${NAMESPACE}"
echo "  kubectl delete namespace ${NAMESPACE}"
