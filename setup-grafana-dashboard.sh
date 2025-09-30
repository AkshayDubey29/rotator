#!/bin/bash

# Setup and Validate Grafana Dashboard for Log Rotator
# Helps import dashboard and verify metrics are available

set -e

echo "📊 Setting up Grafana Dashboard for Log Rotator"
echo "=============================================="
echo ""

# Configuration
GRAFANA_URL=${1:-"http://localhost:3000"}
GRAFANA_USER=${2:-"admin"}
GRAFANA_PASSWORD=${3:-"admin"}
DASHBOARD_FILE="grafana-dashboard.json"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if dashboard file exists
check_dashboard_file() {
    echo "1️⃣ Checking dashboard file..."
    
    if [[ ! -f "$DASHBOARD_FILE" ]]; then
        echo -e "${RED}❌ Dashboard file not found: $DASHBOARD_FILE${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Dashboard file found${NC}"
    
    # Validate JSON
    if jq . "$DASHBOARD_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Dashboard JSON is valid${NC}"
    else
        echo -e "${RED}❌ Dashboard JSON is invalid${NC}"
        exit 1
    fi
}

# Check Grafana connectivity
check_grafana() {
    echo ""
    echo "2️⃣ Checking Grafana connectivity..."
    
    if curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" >/dev/null; then
        echo -e "${GREEN}✅ Grafana is accessible at $GRAFANA_URL${NC}"
    else
        echo -e "${RED}❌ Cannot connect to Grafana at $GRAFANA_URL${NC}"
        echo "   Check URL, credentials, or use port-forward:"
        echo "   kubectl port-forward svc/grafana 3000:3000"
        exit 1
    fi
}

# Check if Prometheus datasource exists
check_datasource() {
    echo ""
    echo "3️⃣ Checking Prometheus datasource..."
    
    DATASOURCES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/datasources")
    
    if echo "$DATASOURCES" | jq -r '.[].type' | grep -q "prometheus"; then
        echo -e "${GREEN}✅ Prometheus datasource found${NC}"
        
        # Show datasource details
        PROM_DS=$(echo "$DATASOURCES" | jq -r '.[] | select(.type=="prometheus") | .name + " (" + .url + ")"')
        echo "   Datasource: $PROM_DS"
    else
        echo -e "${YELLOW}⚠️  No Prometheus datasource found${NC}"
        echo "   Please configure a Prometheus datasource in Grafana first"
        echo "   Datasources → Add datasource → Prometheus"
    fi
}

# Import dashboard
import_dashboard() {
    echo ""
    echo "4️⃣ Importing dashboard..."
    
    # Prepare dashboard JSON for import
    DASHBOARD_JSON=$(jq '{
        dashboard: .,
        overwrite: true,
        inputs: [],
        folderId: 0
    }' "$DASHBOARD_FILE")
    
    # Import dashboard
    IMPORT_RESULT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        -H "Content-Type: application/json" \
        -d "$DASHBOARD_JSON" \
        "$GRAFANA_URL/api/dashboards/import")
    
    if echo "$IMPORT_RESULT" | jq -r '.status' | grep -q "success"; then
        DASHBOARD_ID=$(echo "$IMPORT_RESULT" | jq -r '.id')
        DASHBOARD_UID=$(echo "$IMPORT_RESULT" | jq -r '.uid')
        echo -e "${GREEN}✅ Dashboard imported successfully${NC}"
        echo "   Dashboard ID: $DASHBOARD_ID"
        echo "   Dashboard UID: $DASHBOARD_UID"
        echo "   URL: $GRAFANA_URL/d/$DASHBOARD_UID"
    else
        echo -e "${RED}❌ Dashboard import failed${NC}"
        echo "   Error: $(echo "$IMPORT_RESULT" | jq -r '.message // .error')"
        exit 1
    fi
}

# Verify rotator metrics are available
verify_metrics() {
    echo ""
    echo "5️⃣ Verifying rotator metrics availability..."
    
    # Get Prometheus URL from Grafana
    DATASOURCES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/datasources")
    PROM_URL=$(echo "$DATASOURCES" | jq -r '.[] | select(.type=="prometheus") | .url' | head -1)
    
    if [[ "$PROM_URL" != "null" && -n "$PROM_URL" ]]; then
        echo "   Checking Prometheus at: $PROM_URL"
        
        # Check key rotator metrics
        declare -a METRICS=(
            "up{job=~\".*rotator.*\"}"
            "rotator_scan_cycles_total"
            "rotator_files_discovered"
            "rotator_rotations_total"
            "rotator_errors_total"
        )
        
        for metric in "${METRICS[@]}"; do
            QUERY_RESULT=$(curl -s "$PROM_URL/api/v1/query?query=$metric" | jq -r '.data.result | length')
            
            if [[ "$QUERY_RESULT" -gt 0 ]]; then
                echo -e "   ${GREEN}✅ $metric${NC}"
            else
                echo -e "   ${RED}❌ $metric${NC}"
            fi
        done
    else
        echo -e "${YELLOW}⚠️  Cannot access Prometheus directly${NC}"
        echo "   Dashboard imported, but cannot verify metrics"
        echo "   Check metrics manually in Grafana Explore"
    fi
}

# Provide usage instructions
show_usage_instructions() {
    echo ""
    echo "6️⃣ Usage Instructions:"
    echo ""
    
    echo -e "${BLUE}📊 Dashboard Access:${NC}"
    echo "   Open: $GRAFANA_URL/d/rotator-monitoring"
    echo "   Title: Log Rotator - Comprehensive Monitoring Dashboard"
    echo ""
    
    echo -e "${BLUE}🔧 Configuration:${NC}"
    echo "   1. Verify Prometheus datasource points to your Prometheus server"
    echo "   2. Adjust time range (default: 1 hour)"
    echo "   3. Set up alerts for critical metrics"
    echo ""
    
    echo -e "${BLUE}🎯 Key Panels to Monitor:${NC}"
    echo "   - Service Health (should be 1/UP)"
    echo "   - Scan Activity Rate (should be ~2/minute)"
    echo "   - Error Rate (should be near 0)"
    echo "   - Resource utilization (CPU/Memory)"
    echo ""
    
    echo -e "${BLUE}⚠️  Alerts to Set Up:${NC}"
    echo "   - Service Down: up{job=~\".*rotator.*\"} == 0"
    echo "   - High Error Rate: rate(rotator_errors_total[5m]) > 0.05"
    echo "   - No Activity: increase(rotator_scan_cycles_total[2m]) == 0"
    echo ""
    
    echo -e "${BLUE}📖 Documentation:${NC}"
    echo "   Read: GRAFANA-DASHBOARD.md for detailed usage guide"
}

# Main execution
main() {
    check_dashboard_file
    check_grafana
    check_datasource
    import_dashboard
    verify_metrics
    show_usage_instructions
    
    echo ""
    echo -e "${GREEN}🎉 Dashboard setup completed successfully!${NC}"
    echo ""
    echo "🔗 Quick Links:"
    echo "   Dashboard: $GRAFANA_URL/d/rotator-monitoring"
    echo "   Explore: $GRAFANA_URL/explore"
    echo "   Datasources: $GRAFANA_URL/datasources"
}

# Handle command line arguments
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [grafana_url] [username] [password]"
    echo ""
    echo "Sets up and imports the Log Rotator Grafana dashboard"
    echo ""
    echo "Arguments:"
    echo "  grafana_url    Grafana server URL (default: http://localhost:3000)"
    echo "  username       Grafana username (default: admin)"
    echo "  password       Grafana password (default: admin)"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Use defaults"
    echo "  $0 http://grafana:3000                     # Custom URL"
    echo "  $0 http://grafana:3000 admin mypassword    # Custom credentials"
    echo ""
    echo "Prerequisites:"
    echo "  - Grafana server running and accessible"
    echo "  - Prometheus datasource configured in Grafana"
    echo "  - rotator service deployed and metrics available"
    echo ""
    echo "Port-forward if needed:"
    echo "  kubectl port-forward svc/grafana 3000:3000"
    exit 0
fi

main
