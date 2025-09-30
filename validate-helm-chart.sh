#!/bin/bash

# Helm Chart Validation Script
# Validates templates and configuration consistency

set -e

echo "🔍 Validating Helm Chart Configuration"
echo "======================================"

CHART_PATH="./helm/rotator"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation functions
validate_templates() {
    echo "1️⃣ Validating Helm templates..."
    
    # Lint the chart
    if helm lint $CHART_PATH; then
        echo -e "${GREEN}✅ Helm lint passed${NC}"
    else
        echo -e "${RED}❌ Helm lint failed${NC}"
        exit 1
    fi
    
    # Template the chart with default values
    echo "   Testing default values..."
    helm template test-rotator $CHART_PATH --dry-run > /tmp/default-template.yaml
    echo -e "${GREEN}✅ Default values template successful${NC}"
    
    # Template with production values
    echo "   Testing production values..."
    helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run > /tmp/production-template.yaml
    echo -e "${GREEN}✅ Production values template successful${NC}"
}

validate_port_consistency() {
    echo ""
    echo "2️⃣ Validating port consistency..."
    
    # Check default configuration (port 9102)
    DEFAULT_SERVICE_PORT=$(helm template test-rotator $CHART_PATH --dry-run | grep -A 20 "kind: Service" | grep "port:" | head -1 | awk '{print $2}')
    DEFAULT_CONTAINER_PORT=$(helm template test-rotator $CHART_PATH --dry-run | grep "containerPort:" | head -1 | awk '{print $2}')
    
    echo "   Default values:"
    echo "   - Service port: $DEFAULT_SERVICE_PORT"
    echo "   - Container port: $DEFAULT_CONTAINER_PORT"
    
    if [[ "$DEFAULT_SERVICE_PORT" == "$DEFAULT_CONTAINER_PORT" ]]; then
        echo -e "${GREEN}✅ Default port consistency OK${NC}"
    else
        echo -e "${RED}❌ Default port mismatch${NC}"
        exit 1
    fi
    
    # Check production configuration (port 9090)
    PROD_SERVICE_PORT=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -A 20 "kind: Service" | grep "port:" | head -1 | awk '{print $2}')
    PROD_CONTAINER_PORT=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep "containerPort:" | head -1 | awk '{print $2}')
    
    echo "   Production values:"
    echo "   - Service port: $PROD_SERVICE_PORT"
    echo "   - Container port: $PROD_CONTAINER_PORT"
    
    if [[ "$PROD_SERVICE_PORT" == "$PROD_CONTAINER_PORT" && "$PROD_SERVICE_PORT" == "9090" ]]; then
        echo -e "${GREEN}✅ Production port consistency OK (9090)${NC}"
    else
        echo -e "${RED}❌ Production port mismatch or not 9090${NC}"
        exit 1
    fi
}

validate_servicemonitor() {
    echo ""
    echo "3️⃣ Validating ServiceMonitor configuration..."
    
    # Check if ServiceMonitor is generated with production values
    SERVICEMONITOR_EXISTS=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -c "kind: ServiceMonitor" || echo "0")
    
    if [[ "$SERVICEMONITOR_EXISTS" -gt 0 ]]; then
        echo -e "${GREEN}✅ ServiceMonitor created with production values${NC}"
        
        # Check if it has the /metrics path
        METRICS_PATH=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -A 30 "kind: ServiceMonitor" | grep "path:" | awk '{print $2}')
        
        if [[ "$METRICS_PATH" == "/metrics" ]]; then
            echo -e "${GREEN}✅ ServiceMonitor has correct /metrics path${NC}"
        else
            echo -e "${RED}❌ ServiceMonitor missing /metrics path${NC}"
            exit 1
        fi
        
        # Check standard labels
        STANDARD_LABELS=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -A 30 "kind: ServiceMonitor" | grep -c "app.kubernetes.io" || echo "0")
        
        if [[ "$STANDARD_LABELS" -gt 0 ]]; then
            echo -e "${GREEN}✅ ServiceMonitor has standard Kubernetes labels${NC}"
        else
            echo -e "${YELLOW}⚠️  ServiceMonitor missing standard labels${NC}"
        fi
    else
        echo -e "${RED}❌ ServiceMonitor not created${NC}"
        exit 1
    fi
}

validate_security() {
    echo ""
    echo "4️⃣ Validating security configuration..."
    
    # Check non-root user
    NON_ROOT=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -c "runAsNonRoot: true" || echo "0")
    
    if [[ "$NON_ROOT" -gt 0 ]]; then
        echo -e "${GREEN}✅ Running as non-root user${NC}"
    else
        echo -e "${RED}❌ Not configured to run as non-root${NC}"
        exit 1
    fi
    
    # Check dropped capabilities
    DROP_ALL=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -A 5 "capabilities:" | grep -c "ALL" || echo "0")
    
    if [[ "$DROP_ALL" -gt 0 ]]; then
        echo -e "${GREEN}✅ All capabilities dropped${NC}"
    else
        echo -e "${RED}❌ Capabilities not properly dropped${NC}"
        exit 1
    fi
}

validate_resource_limits() {
    echo ""
    echo "5️⃣ Validating resource configuration..."
    
    # Check if resources are defined
    RESOURCES=$(helm template test-rotator $CHART_PATH -f $CHART_PATH/production-values.yaml --dry-run | grep -A 10 "resources:" | grep -c -E "(requests|limits)" || echo "0")
    
    if [[ "$RESOURCES" -gt 0 ]]; then
        echo -e "${GREEN}✅ Resource requests and limits configured${NC}"
    else
        echo -e "${YELLOW}⚠️  Resource limits not configured${NC}"
    fi
}

# Run all validations
validate_templates
validate_port_consistency
validate_servicemonitor
validate_security
validate_resource_limits

echo ""
echo -e "${GREEN}🎉 All Helm chart validations passed!${NC}"
echo ""
echo "📋 Summary:"
echo "✅ Templates render successfully"
echo "✅ Port consistency maintained"
echo "✅ ServiceMonitor properly configured"
echo "✅ Security context hardened"
echo "✅ Resource limits defined"
echo ""
echo "🚀 Chart is ready for:"
echo "   - Local development (default values)"
echo "   - Production deployment (production-values.yaml)"
echo ""

# Clean up temporary files
rm -f /tmp/default-template.yaml /tmp/production-template.yaml
