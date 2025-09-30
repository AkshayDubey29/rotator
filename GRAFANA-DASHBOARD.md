# 📊 Log Rotator - Comprehensive Grafana Dashboard

## 🎯 **Overview**

This Grafana dashboard provides complete observability for the Log Rotator service, covering:
- **Operational Metrics**: Health, activity, rotations, errors
- **Resource Utilization**: CPU, memory, disk I/O, network I/O
- **Business Metrics**: Namespace usage, policy overrides, storage budgets
- **Performance Indicators**: Minute-level granularity for all metrics

## 📋 **Dashboard Sections**

### **1. Service Overview (Top Row)**
- **Service Health**: Up/Down status indicator
- **Active Pods**: Number of running rotator instances
- **Files Discovered**: Current log files being monitored
- **Total Scan Cycles**: Overall activity counter

### **2. Activity Monitoring**
- **Scan Activity Rate**: Should be ~2 scans/minute (30s intervals)
- **Files Discovered Over Time**: File discovery trends
- **Rotation Rate by Namespace**: Log rotation activity breakdown
- **Data Rotation Rate**: Bytes processed during rotations

### **3. Error & Policy Tracking**
- **Error Rate**: Error frequency by type with alerting thresholds
- **Policy Override Activity**: Namespace and path-specific overrides
- **Namespace Storage Usage**: Budget tracking per namespace

### **4. Resource Utilization**
- **Pod CPU Usage**: Per-pod CPU consumption with thresholds
- **Pod Memory Usage**: Memory utilization tracking
- **Pod Network I/O**: Network traffic patterns
- **Pod Disk I/O**: Critical for log rotation performance

### **5. Key Performance Indicators**
- **Consolidated Stats**: Files monitored, rotations, error rate, resource usage
- **Color-coded Thresholds**: Green/Yellow/Red status indicators

## 🚀 **Installation**

### **Import Dashboard:**
1. Open Grafana → **Dashboards** → **Import**
2. Upload `grafana-dashboard.json` or paste JSON content
3. Configure Prometheus datasource
4. Save dashboard

### **Configure Datasource:**
```yaml
# Ensure your Prometheus datasource includes:
- name: "Prometheus"
  type: "prometheus"
  url: "http://your-prometheus-server:9090"
  access: "proxy"
```

## 📊 **Key Metrics Explained**

### **Health Metrics:**
```promql
# Service availability
up{job=~".*rotator.*"}

# Scan activity (should be ~0.033/sec = 2/min)
rate(rotator_scan_cycles_total[1m])

# Files being monitored
rotator_files_discovered
```

### **Performance Metrics:**
```promql
# Rotation activity
rate(rotator_rotations_total[1m])

# Data throughput
rate(rotator_bytes_rotated_total[1m])

# Error rate
rate(rotator_errors_total[1m])
```

### **Resource Metrics:**
```promql
# CPU usage per pod
rate(container_cpu_usage_seconds_total{pod=~"rotator-.*"}[1m])

# Memory usage per pod
container_memory_working_set_bytes{pod=~"rotator-.*"}

# Disk I/O (critical for rotation performance)
rate(container_fs_writes_bytes_total{pod=~"rotator-.*"}[1m])
```

## ⚠️ **Alert Thresholds**

### **Critical Alerts:**
```yaml
# Service Down
up{job=~".*rotator.*"} == 0

# High Error Rate (>5% of scans)
rate(rotator_errors_total[5m]) / rate(rotator_scan_cycles_total[5m]) > 0.05

# No Scan Activity (>2 minutes without scans)
increase(rotator_scan_cycles_total[2m]) == 0
```

### **Warning Alerts:**
```yaml
# High CPU Usage (>30%)
rate(container_cpu_usage_seconds_total{pod=~"rotator-.*"}[5m]) > 0.3

# High Memory Usage (>256MB)
container_memory_working_set_bytes{pod=~"rotator-.*"} > 268435456

# Low Disk Space (namespace budget >90%)
rotator_ns_usage_bytes / 10737418240 > 0.9  # Assuming 10GB budget
```

## 🔧 **Customization**

### **Time Ranges:**
- **Default**: Last 1 hour with 30-second refresh
- **Recommended**: 6 hours for trend analysis
- **Long-term**: 24 hours for capacity planning

### **Variable Customization:**
```json
# Add namespace filter variable
{
  "name": "namespace",
  "type": "query",
  "query": "label_values(rotator_files_discovered, namespace)",
  "multi": true,
  "includeAll": true
}
```

### **Panel Modifications:**
- **CPU Thresholds**: Adjust based on your resource limits
- **Memory Thresholds**: Match your pod memory requests/limits
- **Error Rate Thresholds**: Set based on your SLA requirements

## 📈 **Usage Patterns**

### **Daily Operations:**
1. **Morning Check**: Service health, overnight rotations
2. **Trend Analysis**: File growth, rotation frequency
3. **Resource Planning**: CPU/memory trends, disk usage

### **Troubleshooting:**
1. **Error Spikes**: Check error rate panel + logs
2. **Performance Issues**: Review resource utilization
3. **Rotation Problems**: Analyze rotation rate vs file discovery

### **Capacity Planning:**
1. **Storage Growth**: Namespace usage trends
2. **Resource Scaling**: CPU/memory patterns
3. **Performance Optimization**: Disk I/O during rotations

## 🎯 **Best Practices**

### **Monitoring:**
- **Set up alerts** for critical metrics
- **Review daily** for operational insights
- **Analyze trends** weekly for capacity planning

### **Performance:**
- **Monitor disk I/O** during heavy rotation periods
- **Track error rates** to identify configuration issues
- **Watch memory growth** for potential memory leaks

### **Operational:**
- **Correlate metrics** with application logs
- **Use annotations** to mark deployment events
- **Export data** for long-term trend analysis

## 🔗 **Related Resources**

- **Application Logs**: `kubectl logs -l app=rotator`
- **Metrics Endpoint**: `http://rotator-service:9090/metrics`
- **Health Endpoint**: `http://rotator-service:9090/live`
- **Configuration**: Helm values and ConfigMaps

---

**Dashboard Version**: 1.0  
**Compatible with**: Grafana 8.0+, Prometheus 2.0+  
**Last Updated**: 2025-09-30  
**Maintainer**: Log Rotator Team
