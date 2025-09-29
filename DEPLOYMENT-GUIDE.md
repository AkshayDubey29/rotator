# Rotator Log Rotation - Complete Deployment Guide

## Prerequisites

Before starting, ensure you have:
- Kubernetes cluster (v1.19+) with admin access
- Docker installed and running
- kubectl configured for your cluster  
- Helm v3.x installed
- Container registry access (Docker Hub, GHCR, etc.)

## Step 1: Clone and Setup Repository

```bash
# Clone the repository
git clone https://github.com/tapasyadubey/log-rotate-util.git
cd log-rotate-util

# Verify structure
ls -la
# Expected: rotator/, helm/, hack/, README.md, etc.
```

## Step 2: Build the Application

```bash
cd rotator

# Install Go dependencies
go mod download
go mod tidy

# Run tests to verify functionality
go test ./...

# Build the binary locally (optional verification)
go build -o bin/rotator ./cmd/rotator
./bin/rotator --help
```

## Step 3: Build and Push Container Image

### Option A: Using Docker Hub
```bash
# Set your registry details
export REGISTRY="your-dockerhub-username"
export IMAGE_NAME="rotator"
export TAG="v1.0.0"

# Build the image
docker build -t ${REGISTRY}/${IMAGE_NAME}:${TAG} -f Dockerfile .

# Test the image locally
docker run --rm ${REGISTRY}/${IMAGE_NAME}:${TAG} --help

# Push to registry
docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}
```

### Option B: Using GitHub Container Registry (GHCR)
```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Set registry details
export REGISTRY="ghcr.io/your-github-username"
export IMAGE_NAME="rotator"
export TAG="v1.0.0"

# Build and push
docker build -t ${REGISTRY}/${IMAGE_NAME}:${TAG} -f Dockerfile .
docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}
```

## Step 4: Prepare Kubernetes Cluster

```bash
# Create namespace (optional)
kubectl create namespace log-rotation

# Create log directory on nodes (for demo)
# Note: In production, this should be handled by node setup
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: prepare-log-dirs
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
kubectl wait --for=condition=complete job/prepare-log-dirs --timeout=60s

# Clean up the job
kubectl delete job prepare-log-dirs
```

## Step 5: Configure Helm Values

```bash
cd ../helm/rotator

# Create custom values file
cat > production-values.yaml <<EOF
rotator:
  image:
    repository: ${REGISTRY}/${IMAGE_NAME}
    tag: ${TAG}
    pullPolicy: IfNotPresent
  
  # Adjust resources for your environment
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  # Customize for your environment
  defaults:
    discovery:
      path: /pang/logs
      include: ["**/*.log", "**/*.out", "**/*.jsonl"]
      exclude: ["**/*.gz", "**/*.zip", "**/*.tmp"]
      maxDepth: 8
    policy:
      size: 100Mi          # Rotate when file exceeds 100MB
      age: 24h             # Rotate files older than 24h
      inactive: 6h         # Rotate inactive files after 6h
      keepFiles: 5         # Keep 5 rotated files
      keepDays: 7          # Keep files for 7 days
      compressAfter: 1h    # Compress after 1 hour
      defaultMode: rename  # Use rename technique
    budgets:
      perNamespaceBytes: 10Gi  # 10GB per namespace limit
  
  # Environment-specific overrides
  overrides:
    namespaces:
      # High-traffic namespace with smaller rotation
      production:
        policy:
          size: 50Mi
          defaultMode: copytruncate
        budgets:
          perNamespaceBytes: 20Gi
      
      # Development namespace with longer retention
      development:
        policy:
          keepFiles: 10
          keepDays: 14
      
      # Critical namespace with frequent rotation
      critical:
        policy:
          size: 25Mi
          age: 6h
          compressAfter: 30m
        budgets:
          perNamespaceBytes: 50Gi

# Security settings (production-ready)
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  fsGroup: 65534

# Monitoring (enable if Prometheus Operator available)
serviceMonitor:
  enabled: false  # Set to true if you have Prometheus Operator

# Priority for critical workload
priorityClass:
  create: false
  name: system-node-critical
EOF
```

## Step 6: Deploy Using Helm

```bash
# Validate the chart
helm lint .

# Dry run to verify configuration
helm install rotator . \
  --values production-values.yaml \
  --dry-run --debug

# Install the application
helm install rotator . \
  --values production-values.yaml \
  --namespace log-rotation \
  --create-namespace

# Verify deployment
helm status rotator -n log-rotation
```

## Step 7: Verify Deployment

```bash
# Check pod status
kubectl get pods -n log-rotation -l app=rotator

# Check DaemonSet status
kubectl get daemonset -n log-rotation

# View logs
kubectl logs -n log-rotation -l app=rotator

# Check health endpoints
kubectl port-forward -n log-rotation daemonset/rotator 9102:9102 &
curl http://localhost:9102/live
curl http://localhost:9102/ready
curl http://localhost:9102/metrics
```

## Step 8: Deploy Demo Applications (Optional)

```bash
# Create demo namespaces
kubectl create namespace payments
kubectl create namespace checkout  
kubectl create namespace shipping

# Deploy log-generating applications
kubectl apply -n payments -f ../../hack/log-writer-daemonset.yaml
kubectl apply -n checkout -f ../../hack/log-writer-daemonset.yaml
kubectl apply -n shipping -f ../../hack/log-writer-daemonset.yaml

# Wait for pods to start
kubectl get pods -n payments -l app=demo-log-writer
kubectl get pods -n checkout -l app=demo-log-writer
kubectl get pods -n shipping -l app=demo-log-writer
```

## Step 9: Monitor and Validate

```bash
# Monitor rotator metrics
kubectl port-forward -n log-rotation daemonset/rotator 9102:9102 &

# Check metrics (in another terminal)
curl -s http://localhost:9102/metrics | grep rotator_

# Watch log files being created and rotated
kubectl exec -n log-rotation $(kubectl get pods -n log-rotation -l app=rotator -o name | head -1) -- find /pang/logs -type f

# Monitor rotator logs
kubectl logs -n log-rotation -l app=rotator -f
```

## Step 10: Production Monitoring Setup

### Enable Prometheus Monitoring
```bash
# Update values to enable ServiceMonitor
helm upgrade rotator . \
  --values production-values.yaml \
  --set serviceMonitor.enabled=true \
  --namespace log-rotation

# Verify ServiceMonitor creation
kubectl get servicemonitor -n log-rotation
```

### Setup Grafana Dashboard
```bash
# Example Grafana dashboard JSON (save as rotator-dashboard.json)
cat > rotator-dashboard.json <<'EOF'
{
  "dashboard": {
    "title": "Rotator Log Rotation",
    "panels": [
      {
        "title": "Rotation Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(rotator_rotations_total[5m])",
            "legendFormat": "{{namespace}} - {{technique}}"
          }
        ]
      },
      {
        "title": "Namespace Usage",
        "type": "gauge", 
        "targets": [
          {
            "expr": "rotator_ns_usage_bytes",
            "legendFormat": "{{namespace}}"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(rotator_errors_total[5m])",
            "legendFormat": "{{type}}"
          }
        ]
      }
    ]
  }
}
EOF
```

## Step 11: Cleanup (When Needed)

```bash
# Remove demo applications
kubectl delete namespace payments checkout shipping

# Remove rotator
helm uninstall rotator -n log-rotation

# Remove namespace
kubectl delete namespace log-rotation

# Clean up container images
docker rmi ${REGISTRY}/${IMAGE_NAME}:${TAG}
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Check file permissions
   kubectl exec -n log-rotation $(kubectl get pods -n log-rotation -l app=rotator -o name | head -1) -- ls -la /pang/logs
   
   # Fix permissions on nodes
   kubectl apply -f - <<EOF
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: fix-permissions
   spec:
     template:
       spec:
         containers:
         - name: fix
           image: alpine
           command: ["/bin/sh", "-c"]
           args: ["chown -R 65534:65534 /host/pang/logs"]
           volumeMounts:
           - name: host-logs
             mountPath: /host/pang/logs
         volumes:
         - name: host-logs
           hostPath:
             path: /pang/logs
         restartPolicy: Never
   EOF
   ```

2. **Image Pull Errors**
   ```bash
   # Check image exists
   docker pull ${REGISTRY}/${IMAGE_NAME}:${TAG}
   
   # Create image pull secret if using private registry
   kubectl create secret docker-registry regcred \
     --docker-server=${REGISTRY} \
     --docker-username=USERNAME \
     --docker-password=PASSWORD \
     --namespace=log-rotation
   
   # Update values to use image pull secret
   # Add to production-values.yaml:
   # imagePullSecrets:
   #   - name: regcred
   ```

3. **Health Check Failures**
   ```bash
   # Check rotator logs
   kubectl logs -n log-rotation -l app=rotator
   
   # Test endpoints manually
   kubectl exec -n log-rotation $(kubectl get pods -n log-rotation -l app=rotator -o name | head -1) -- wget -qO- http://localhost:9102/live
   ```

## Production Checklist

- [ ] Container image built and pushed to registry
- [ ] Production values.yaml configured for your environment  
- [ ] Log directories created on all nodes with proper permissions
- [ ] Helm chart deployed successfully
- [ ] Health checks passing
- [ ] Metrics endpoint accessible
- [ ] Log rotation working (verify with demo applications)
- [ ] Monitoring and alerting configured
- [ ] Backup strategy for journal state defined
- [ ] Documentation updated for your environment

## Security Considerations

1. **Registry Security**: Use private registries for production images
2. **RBAC**: Review and minimize cluster permissions
3. **Network Policies**: Add network policies to restrict traffic
4. **Image Scanning**: Scan images for vulnerabilities before deployment
5. **Secrets Management**: Use proper secret management for sensitive config

Your rotator application is now deployed and ready for production log rotation!
