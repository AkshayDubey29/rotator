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
		reg: r,
	}
	r.MustRegister(m.RotationsTotal, m.BytesRotatedTotal, m.ErrorsTotal, m.NamespaceUsageBytes, m.OverridesApplied, m.ScanCycles)
	return m
}

func (r *Registry) Handler() http.Handler { return promhttp.HandlerFor(r.reg, promhttp.HandlerOpts{}) }

func (r *Registry) CountError(t string) { r.ErrorsTotal.WithLabelValues(t).Inc() }
