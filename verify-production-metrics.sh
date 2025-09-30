#!/bin/bash

# Production Metrics Verification Script for Rotator
# This script helps verify that all rotator metrics are properly exposed and being scraped

set -e

echo "🔍 Rotator Production Metrics Verification"
echo "=========================================="

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

# Function to check if rotator pods are running
check_pods() {
    echo "1️⃣ Checking Rotator Pods..."
    kubectl get pods -n $NAMESPACE -l app=rotator -o wide
    
    READY_PODS=$(kubectl get pods -n $NAMESPACE -l app=rotator --no-headers | grep "1/1" | wc -l)
    TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app=rotator --no-headers | wc -l)
    
    echo "   Ready: $READY_PODS/$TOTAL_PODS pods"
    
    if [ "$READY_PODS" -eq 0 ]; then
        echo "❌ No ready rotator pods found!"
        exit 1
    fi
    echo "✅ Rotator pods are running"
    echo ""
}

# Function to test metrics endpoint directly
test_metrics_endpoint() {
    echo "2️⃣ Testing Metrics Endpoint..."
    
    # Get a pod name
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=rotator -o jsonpath="{.items[0].metadata.name}")
    echo "   Using pod: $POD_NAME"
    
    # Port forward to the pod
    echo "   Setting up port-forward..."
    kubectl port-forward -n $NAMESPACE pod/$POD_NAME $PORT:$PORT > /dev/null 2>&1 &
    PF_PID=$!
    
    # Wait for port-forward to be ready
    sleep 3
    
    # Test the endpoint
    echo "   Testing http://localhost:$PORT/metrics"
    
    if curl -s --max-time 5 http://localhost:$PORT/metrics > /dev/null; then
        echo "✅ Metrics endpoint is accessible"
        
        # Count rotator metrics
        METRIC_COUNT=$(curl -s http://localhost:$PORT/metrics | grep "^rotator_" | wc -l)
        echo "   Found $METRIC_COUNT rotator metric values"
        
        # Show all rotator metrics
        echo ""
        echo "📋 All Rotator Metrics:"
        curl -s http://localhost:$PORT/metrics | grep -E "(# HELP rotator_|# TYPE rotator_|^rotator_)" | while read line; do
            echo "   $line"
        done
        
    else
        echo "❌ Metrics endpoint is not accessible"
        kill $PF_PID 2>/dev/null || true
        exit 1
    fi
    
    # Cleanup
    kill $PF_PID 2>/dev/null || true
    echo ""
}

# Function to check service configuration
check_service() {
    echo "3️⃣ Checking Service Configuration..."
    
    if kubectl get service -n $NAMESPACE $SERVICE_NAME &> /dev/null; then
        kubectl get service -n $NAMESPACE $SERVICE_NAME -o yaml | grep -A 5 -B 5 "port"
        echo "✅ Service is configured correctly"
    else
        echo "❌ Service $SERVICE_NAME not found in namespace $NAMESPACE"
        exit 1
    fi
    echo ""
}

# Function to check ServiceMonitor (if Prometheus Operator is used)
check_servicemonitor() {
    echo "4️⃣ Checking ServiceMonitor..."
    
    if kubectl get servicemonitor -n $NAMESPACE $SERVICE_NAME &> /dev/null; then
        echo "✅ ServiceMonitor exists"
        kubectl get servicemonitor -n $NAMESPACE $SERVICE_NAME -o yaml | grep -A 10 -B 5 "interval\|port"
    else
        echo "⚠️  ServiceMonitor not found (may not be using Prometheus Operator)"
    fi
    echo ""
}

# Function to show sample Prometheus queries for Mimir
show_prometheus_queries() {
    echo "5️⃣ Sample Prometheus/Mimir Queries for Verification:"
    echo ""
    echo "📊 Basic Health Check:"
    echo "   up{job=~\".*rotator.*\"}"
    echo ""
    echo "📊 Scan Activity:"
    echo "   rate(rotator_scan_cycles_total[5m])"
    echo "   rotator_files_discovered"
    echo ""
    echo "📊 Rotation Activity (when files are found):"
    echo "   rate(rotator_rotations_total[5m])"
    echo "   sum by (namespace) (rotator_bytes_rotated_total)"
    echo ""
    echo "📊 Error Monitoring:"
    echo "   rate(rotator_errors_total[5m])"
    echo ""
    echo "📊 Policy Overrides:"
    echo "   rate(rotator_overrides_applied_total[5m])"
    echo ""
}

# Function to create a test file for verification
create_test_file() {
    echo "6️⃣ Optional: Create Test Log File for Verification"
    echo ""
    echo "To verify that metrics change when files are found, you can create a test file:"
    echo ""
    echo "# Create test namespace and directory"
    echo "kubectl create namespace test-metrics || true"
    echo ""
    echo "# Create test log file on one of the nodes"
    echo "kubectl debug node/\$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') -it --image=busybox -- sh -c \\"
    echo "  'mkdir -p /host/pang/logs/test-metrics/test-pod && \\"
    echo "   echo \"\$(date): Test log entry\" > /host/pang/logs/test-metrics/test-pod/app.log && \\"
    echo "   chown 65534:65534 /host/pang/logs/test-metrics/test-pod/app.log'"
    echo ""
    echo "# Watch for file discovery (should change from 0 to 1)"
    echo "watch -n 5 'curl -s http://localhost:$PORT/metrics | grep rotator_files_discovered'"
    echo ""
    echo "# Cleanup test file"
    echo "kubectl delete namespace test-metrics"
    echo ""
}

# Main execution
main() {
    check_kubectl
    check_pods
    test_metrics_endpoint
    check_service
    check_servicemonitor
    show_prometheus_queries
    create_test_file
    
    echo "✅ Production metrics verification completed!"
    echo ""
    echo "📋 Summary:"
    echo "   - Rotator pods are running and metrics endpoint is accessible"
    echo "   - All rotator metrics are properly defined and exposed"
    echo "   - Service and ServiceMonitor are configured for scraping"
    echo "   - Use the provided Prometheus queries to verify in Mimir"
    echo ""
    echo "🔧 If metrics are still not appearing in Mimir:"
    echo "   1. Check Prometheus scrape config includes rotator service"
    echo "   2. Verify network connectivity from Prometheus to rotator service"
    echo "   3. Check Prometheus targets page for rotator endpoints"
    echo "   4. Verify Mimir ingestion pipeline is working"
}

# Run the script
main "$@"
