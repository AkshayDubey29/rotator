# Rotator Baseline Metrics for Mimir Verification

## 🎯 **Answer: YES - Multiple metrics appear immediately, regardless of files_found count**

Even with **0 files found**, the rotator exposes these baseline metrics that should appear in Mimir immediately:

## ✅ **Baseline Metrics (Always Available)**

### **1. Scan Activity (PRIMARY HEALTH INDICATOR)**
```promql
# This ALWAYS increments every 30 seconds when rotator is healthy
rotator_scan_cycles_total

# Current value from test: 89 (proves rotator is actively running)
```

### **2. File Discovery**
```promql
# Shows discovered files (can be 0, but metric always exists)
rotator_files_discovered

# Current value from test: 3 (but would be 0 with no files)
```

### **3. Pre-initialized Counters (Always 0 Until Activity)**
```promql
# Rotation activity
rotator_rotations_total{namespace="_default",technique="rename"}

# Bytes processed  
rotator_bytes_rotated_total{namespace="_default"}

# Namespace usage
rotator_ns_usage_bytes{namespace="_default"}

# Error tracking
rotator_errors_total{type="discovery"}
```

### **4. Policy Override Activity**
```promql
# Namespace overrides applied (increments when namespace policies are used)
rotator_overrides_applied_total{type="namespace"}

# Path overrides applied  
rotator_overrides_applied_total{type="path"}

# Current test values: namespace=267, path=0
```

### **5. Standard Prometheus Health**
```promql
# Should be 1 when rotator is scraped successfully
up{job=~".*rotator.*"}
```

## 🔍 **Test Results from Local Environment**

**Current Metrics Output:**
```
rotator_bytes_rotated_total{namespace="_default"} 0
rotator_errors_total{type="discovery"} 0
rotator_files_discovered 3
rotator_ns_usage_bytes{namespace="_default"} 0
rotator_overrides_applied_total{type="namespace"} 267
rotator_overrides_applied_total{type="path"} 0
rotator_rotations_total{namespace="_default",technique="rename"} 0
rotator_scan_cycles_total 89
```

## 🚀 **Immediate Mimir Verification Queries**

### **Health Check (Should work immediately):**
```promql
# Service is up and being scraped
up{job=~".*rotator.*"}

# Rotator is actively scanning (increments every 30s)
rotator_scan_cycles_total

# Rate of scan activity (should be ~2/minute = 0.033/second)
rate(rotator_scan_cycles_total[5m])
```

### **Activity Monitoring:**
```promql
# Files currently being monitored
rotator_files_discovered

# Override policy usage
rotator_overrides_applied_total

# Error rate (should be 0)
rate(rotator_errors_total[5m])
```

### **System Health Dashboard:**
```promql
# Uptime indicator
up{job=~".*rotator.*"}

# Scan frequency (healthy = ~0.033/sec)
rate(rotator_scan_cycles_total[1m])

# Error percentage (healthy = 0%)
rate(rotator_errors_total[5m]) / rate(rotator_scan_cycles_total[5m]) * 100
```

## 🎯 **Key Insights**

1. **✅ `rotator_scan_cycles_total`** - **MOST IMPORTANT**: This increments every 30 seconds regardless of files found. If this appears and increments, your Mimir integration is working.

2. **✅ `rotator_overrides_applied_total{type="namespace"}`** - Shows policy engine activity (267 in test = active namespace policy evaluation).

3. **✅ All metrics initialized** - Even unused metrics appear with 0 values, so you get full visibility.

4. **✅ `up{}` metric** - Prometheus standard health metric should be 1 when scraping works.

## 🔧 **Troubleshooting Guide**

### **If NO metrics appear in Mimir:**
```bash
# 1. Check ServiceMonitor exists
kubectl get servicemonitor rotator -n log-rotation

# 2. Check Grafana Agent logs for scrape errors  
kubectl logs -n monitoring -l app=grafana-agent | grep rotator

# 3. Verify ServiceMonitor labels match Agent config
kubectl get servicemonitor rotator -n log-rotation -o yaml
```

### **If rotator_scan_cycles_total is 0 or not incrementing:**
```bash
# Check rotator pod logs
kubectl logs -l app=rotator --tail=20

# Should see: {"files_found":N,"level":"info","msg":"scan cycle"}
```

### **Expected Timeline:**
- **0-30 seconds**: Metrics appear in Mimir (if ServiceMonitor working)
- **30 seconds**: First `rotator_scan_cycles_total` increment
- **60 seconds**: Second increment (confirms continuous operation)

## ✅ **SUCCESS CRITERIA**

Your Mimir integration is working if you can query:
```promql
rotator_scan_cycles_total > 0
```

And it increases every 30 seconds, regardless of `files_found` count!

---

**📊 The rotator exposes 8 different metric series immediately, providing rich observability even in zero-file environments.**
