#!/bin/bash

# Test Dashboard Queries for Kubernetes Environment
# Validates that dashboard queries work with your specific label setup

echo "🔍 Testing Dashboard Queries for Kubernetes Environment"
echo "====================================================="
echo ""

# Configuration
PROMETHEUS_URL=${1:-"http://localhost:9090"}
NAMESPACE=${2:-"log-rotation"}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🎯 Testing against: $PROMETHEUS_URL"
echo "📍 Namespace: $NAMESPACE"
echo ""

# Test queries from the dashboard
declare -A QUERIES=(
    ["Service Health"]='up{kubernetes_name="rotator"} OR up{app="rotator"} OR up{job=~".*rotator.*"} OR up{kubernetes_io_app_name="rotator"}'
    ["Active Pods"]='count((up{kubernetes_name="rotator"} OR up{app="rotator"} OR up{job=~".*rotator.*"} OR up{kubernetes_io_app_name="rotator"}) == 1)'
    ["Files Monitored"]='sum(rotator_files_discovered)'
    ["Errors (5m)"]='sum(increase(rotator_errors_total[5m]))'
    ["Rotations (5m)"]='sum(increase(rotator_rotations_total[5m]))'
    ["Error Rate %"]='sum(rate(rotator_errors_total[5m])) / sum(rate(rotator_scan_cycles_total[5m])) * 100'
    ["Scan Activity"]='rate(rotator_scan_cycles_total[1m]) * 60'
    ["Error Details"]='rate(rotator_errors_total[1m]) * 60'
    ["Failed Files"]='increase(rotator_errors_total{type="rotation_failed"}[5m])'
    ["CPU Usage"]='rate(container_cpu_usage_seconds_total{pod=~"rotator-.*"}[1m])'
    ["Memory Usage"]='container_memory_working_set_bytes{pod=~"rotator-.*"}'
)

test_query() {
    local name="$1"
    local query="$2"
    
    echo -n "   Testing: $name... "
    
    # URL encode the query
    local encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
    
    # Execute query
    local result=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$encoded_query" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Connection failed${NC}"
        return 1
    fi
    
    # Check if query succeeded
    local status=$(echo "$result" | jq -r '.status' 2>/dev/null)
    
    if [[ "$status" == "success" ]]; then
        local result_count=$(echo "$result" | jq -r '.data.result | length' 2>/dev/null)
        
        if [[ "$result_count" -gt 0 ]]; then
            echo -e "${GREEN}✅ ($result_count results)${NC}"
            
            # Show sample values for key metrics
            if [[ "$name" == "Service Health" || "$name" == "Active Pods" || "$name" == "Files Monitored" ]]; then
                local value=$(echo "$result" | jq -r '.data.result[0].value[1]' 2>/dev/null)
                echo "      Value: $value"
            fi
        else
            echo -e "${YELLOW}⚠️  No data${NC}"
        fi
    else
        local error=$(echo "$result" | jq -r '.error' 2>/dev/null)
        echo -e "${RED}❌ Query error: $error${NC}"
    fi
}

# Test all dashboard queries
echo "1️⃣ Testing Dashboard Queries:"
echo ""

for query_name in "${!QUERIES[@]}"; do
    test_query "$query_name" "${QUERIES[$query_name]}"
done

echo ""

# Test specific Kubernetes label patterns
echo "2️⃣ Testing Kubernetes Label Patterns:"
echo ""

declare -A LABEL_TESTS=(
    ["kubernetes_name"]='up{kubernetes_name="rotator"}'
    ["app label"]='up{app="rotator"}'
    ["job pattern"]='up{job=~".*rotator.*"}'
    ["kubernetes_io_app_name"]='up{kubernetes_io_app_name="rotator"}'
)

for label_name in "${!LABEL_TESTS[@]}"; do
    test_query "$label_name" "${LABEL_TESTS[$label_name]}"
done

echo ""

# Check for rotator-specific metrics
echo "3️⃣ Checking Rotator-Specific Metrics:"
echo ""

declare -a ROTATOR_METRICS=(
    "rotator_scan_cycles_total"
    "rotator_files_discovered"
    "rotator_rotations_total"
    "rotator_errors_total"
    "rotator_bytes_rotated_total"
    "rotator_ns_usage_bytes"
    "rotator_overrides_applied_total"
)

for metric in "${ROTATOR_METRICS[@]}"; do
    test_query "$metric" "$metric"
done

echo ""

# Provide recommendations
echo "4️⃣ Recommendations:"
echo ""

echo -e "${BLUE}📊 Dashboard Import:${NC}"
echo "   If queries work, import: grafana-dashboard.json"
echo "   Dashboard UID: rotator-production"
echo ""

echo -e "${BLUE}🔧 If Service Health fails:${NC}"
echo "   1. Check which label pattern works from section 2"
echo "   2. Update dashboard query to use working pattern"
echo "   3. Common patterns:"
echo "      - up{app=\"rotator\"}"
echo "      - up{kubernetes_name=\"rotator\"}"
echo "      - up{job=\"rotator\"}"
echo ""

echo -e "${BLUE}⚠️  If No Rotator Metrics:${NC}"
echo "   1. Check rotator service is running: kubectl get pods -l app=rotator"
echo "   2. Verify metrics endpoint: kubectl port-forward svc/rotator 9090:9090"
echo "   3. Test metrics: curl http://localhost:9090/metrics | grep rotator"
echo "   4. Check ServiceMonitor/annotations are configured"
echo ""

echo -e "${BLUE}🎯 Success Criteria:${NC}"
echo "   ✅ Service Health returns 1"
echo "   ✅ Active Pods > 0"
echo "   ✅ At least 3 rotator metrics available"
echo "   ✅ No query errors"

# Final summary
echo ""
echo "📋 Test completed. Import dashboard if most queries succeeded."
echo "   Dashboard file: grafana-dashboard.json"
echo "   Setup script: ./setup-grafana-dashboard.sh"
