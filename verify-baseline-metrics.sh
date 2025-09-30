#!/bin/bash

# Verify Baseline Metrics - Test what should appear immediately when rotator starts
# This script helps verify Mimir integration even with zero files

set -e

echo "🔍 Verifying Baseline Metrics for Rotator"
echo "========================================="
echo ""

# Configuration
METRICS_PORT=${1:-9102}
POD_NAME=""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Find rotator pod
find_pod() {
    echo "1️⃣ Finding rotator pod..."
    POD_NAME=$(kubectl get pods -l app=rotator -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [[ -z "$POD_NAME" ]]; then
        echo -e "${RED}❌ No rotator pod found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Found pod: $POD_NAME${NC}"
    
    # Check pod status
    POD_STATUS=$(kubectl get pod $POD_NAME -o jsonpath="{.status.phase}")
    echo "   Pod status: $POD_STATUS"
    
    if [[ "$POD_STATUS" != "Running" ]]; then
        echo -e "${RED}❌ Pod not running${NC}"
        exit 1
    fi
}

# Test metrics endpoint accessibility
test_endpoint() {
    echo ""
    echo "2️⃣ Testing metrics endpoint..."
    
    # Test internal access
    echo "   Testing internal access on port $METRICS_PORT..."
    if kubectl exec $POD_NAME -- wget -qO- http://localhost:$METRICS_PORT/metrics >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Metrics endpoint accessible internally${NC}"
    else
        echo -e "${RED}❌ Metrics endpoint not accessible internally${NC}"
        
        # Try other common ports
        for port in 9090 9102; do
            if [[ "$port" != "$METRICS_PORT" ]]; then
                echo "   Trying port $port..."
                if kubectl exec $POD_NAME -- wget -qO- http://localhost:$port/metrics >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠️  Found metrics on port $port instead of $METRICS_PORT${NC}"
                    METRICS_PORT=$port
                    break
                fi
            fi
        done
    fi
}

# Check baseline metrics that should always be present
check_baseline_metrics() {
    echo ""
    echo "3️⃣ Checking baseline metrics (should appear immediately)..."
    
    # Get all metrics
    ALL_METRICS=$(kubectl exec $POD_NAME -- wget -qO- http://localhost:$METRICS_PORT/metrics 2>/dev/null)
    
    # Define expected baseline metrics
    declare -a EXPECTED_METRICS=(
        "rotator_scan_cycles_total"
        "rotator_files_discovered"
        "rotator_rotations_total"
        "rotator_bytes_rotated_total"
        "rotator_ns_usage_bytes"
        "rotator_overrides_applied_total"
        "rotator_errors_total"
    )
    
    echo "   Expected baseline metrics:"
    
    for metric in "${EXPECTED_METRICS[@]}"; do
        if echo "$ALL_METRICS" | grep -q "^$metric"; then
            VALUE=$(echo "$ALL_METRICS" | grep "^$metric" | head -1 | awk '{print $2}')
            echo -e "${GREEN}   ✅ $metric: $VALUE${NC}"
        else
            echo -e "${RED}   ❌ $metric: MISSING${NC}"
        fi
    done
}

# Check scan activity (should increment over time)
check_scan_activity() {
    echo ""
    echo "4️⃣ Checking scan activity (should increment every 30s)..."
    
    # Get initial scan count
    INITIAL_SCANS=$(kubectl exec $POD_NAME -- wget -qO- http://localhost:$METRICS_PORT/metrics 2>/dev/null | grep "^rotator_scan_cycles_total" | awk '{print $2}')
    
    if [[ -z "$INITIAL_SCANS" ]]; then
        echo -e "${RED}❌ rotator_scan_cycles_total not found${NC}"
        return
    fi
    
    echo "   Initial scan count: $INITIAL_SCANS"
    echo "   Waiting 35 seconds for next scan cycle..."
    
    sleep 35
    
    # Get new scan count
    NEW_SCANS=$(kubectl exec $POD_NAME -- wget -qO- http://localhost:$METRICS_PORT/metrics 2>/dev/null | grep "^rotator_scan_cycles_total" | awk '{print $2}')
    
    echo "   New scan count: $NEW_SCANS"
    
    if (( $(echo "$NEW_SCANS > $INITIAL_SCANS" | bc -l) )); then
        echo -e "${GREEN}✅ Scan cycles are incrementing (rotator is active)${NC}"
    else
        echo -e "${RED}❌ Scan cycles not incrementing (rotator may be stuck)${NC}"
    fi
}

# Display current metrics for Mimir testing
show_mimir_queries() {
    echo ""
    echo "5️⃣ Mimir/Grafana Test Queries:"
    echo ""
    
    # Get current metrics
    CURRENT_METRICS=$(kubectl exec $POD_NAME -- wget -qO- http://localhost:$METRICS_PORT/metrics 2>/dev/null)
    
    echo -e "${BLUE}📊 Use these queries in Mimir/Grafana:${NC}"
    echo ""
    echo "# Health check (should be 1)"
    echo "up{job=~\".*rotator.*\"}"
    echo ""
    echo "# Scan activity (should increment every 30s)"
    echo "rotator_scan_cycles_total"
    echo ""
    echo "# Files discovered (may be 0, but metric should exist)"
    echo "rotator_files_discovered"
    echo ""
    echo "# Error rate (should be 0 normally)"
    echo "rate(rotator_errors_total[5m])"
    echo ""
    
    # Show current values
    echo -e "${BLUE}📈 Current metric values:${NC}"
    echo "$CURRENT_METRICS" | grep "^rotator_" | while read line; do
        echo "   $line"
    done
}

# Check logs for any obvious issues
check_logs() {
    echo ""
    echo "6️⃣ Checking recent logs..."
    
    echo "   Last 10 log entries:"
    kubectl logs $POD_NAME --tail=10 | while read line; do
        echo "   $line"
    done
}

# Run all checks
main() {
    find_pod
    test_endpoint
    check_baseline_metrics
    check_scan_activity
    show_mimir_queries
    check_logs
    
    echo ""
    echo -e "${GREEN}🎯 Summary:${NC}"
    echo "✅ Even with 0 files found, you should see:"
    echo "   - rotator_scan_cycles_total (incrementing every 30s)"
    echo "   - rotator_files_discovered (value: 0)"
    echo "   - All other rotator_* metrics (initialized to 0)"
    echo "   - up{job=~\".*rotator.*\"} (value: 1)"
    echo ""
    echo "🔧 If metrics don't appear in Mimir:"
    echo "   1. Check ServiceMonitor exists: kubectl get servicemonitor rotator"
    echo "   2. Check Grafana Agent logs for scrape errors"
    echo "   3. Verify ServiceMonitor labels match Agent config"
    echo "   4. Use queries above to test in Mimir/Grafana"
    echo ""
}

# Handle command line arguments
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [metrics_port]"
    echo ""
    echo "Verifies baseline metrics that should appear immediately when rotator starts."
    echo "Useful for testing Mimir integration even with zero log files."
    echo ""
    echo "Arguments:"
    echo "  metrics_port    Port where metrics are exposed (default: 9102)"
    echo ""
    echo "Examples:"
    echo "  $0              # Use default port 9102"
    echo "  $0 9090         # Use port 9090"
    exit 0
fi

main
