package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Registry struct {
	RotationsTotal      *prometheus.CounterVec
	BytesRotatedTotal   *prometheus.CounterVec
	ErrorsTotal         *prometheus.CounterVec
	NamespaceUsageBytes *prometheus.GaugeVec
	OverridesApplied    *prometheus.CounterVec
	ScanCycles          prometheus.Counter
	FilesDiscovered     prometheus.Gauge
	reg                 *prometheus.Registry
}

func NewRegistry() *Registry {
	r := prometheus.NewRegistry()
	m := &Registry{
		RotationsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "rotator_rotations_total",
			Help: "Total number of rotations performed",
		}, []string{"namespace", "technique"}),
		BytesRotatedTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "rotator_bytes_rotated_total",
			Help: "Total bytes rotated per namespace",
		}, []string{"namespace"}),
		ErrorsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "rotator_errors_total",
			Help: "Total number of errors by type",
		}, []string{"type"}),
		NamespaceUsageBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "rotator_ns_usage_bytes",
			Help: "Per-namespace archived usage in bytes",
		}, []string{"namespace"}),
		OverridesApplied: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "rotator_overrides_applied_total",
			Help: "Overrides applied count by type",
		}, []string{"type"}),
		ScanCycles: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "rotator_scan_cycles_total",
			Help: "Total number of scan cycles performed",
		}),
		FilesDiscovered: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "rotator_files_discovered",
			Help: "Current number of log files discovered",
		}),
		reg: r,
	}
	r.MustRegister(m.RotationsTotal, m.BytesRotatedTotal, m.ErrorsTotal, m.NamespaceUsageBytes, m.OverridesApplied, m.ScanCycles, m.FilesDiscovered)
	
	// Initialize all metrics so they appear in /metrics endpoint even with zero values
	m.FilesDiscovered.Set(0)
	m.RotationsTotal.WithLabelValues("_default", "rename").Add(0)        // Initialize with dummy labels
	m.BytesRotatedTotal.WithLabelValues("_default").Add(0)               // Will show up as zero
	m.NamespaceUsageBytes.WithLabelValues("_default").Set(0)             // Will show up as zero
	m.OverridesApplied.WithLabelValues("namespace").Add(0)               // Will show up as zero
	m.OverridesApplied.WithLabelValues("path").Add(0)                    // Will show up as zero
	m.ErrorsTotal.WithLabelValues("discovery").Add(0)                    // Will show up as zero
	
	return m
}

func (r *Registry) Handler() http.Handler { return promhttp.HandlerFor(r.reg, promhttp.HandlerOpts{}) }

func (r *Registry) CountError(t string) { r.ErrorsTotal.WithLabelValues(t).Inc() }
