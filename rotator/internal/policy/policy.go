package policy

import (
	"path/filepath"
	"strings"

	"github.com/bmatcuk/doublestar/v4"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/config"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/metrics"
)

type Engine struct {
	cfg *config.Config
	m   *metrics.Registry
}

func New(cfg *config.Config, m *metrics.Registry) *Engine {
	return &Engine{cfg: cfg, m: m}
}

// EffectivePolicy merges defaults -> namespace override -> path override
func (e *Engine) EffectivePolicy(namespace, fullPath string) config.PolicyConfig {
	eff := e.cfg.Defaults.Policy

	// namespace-level
	if ns, ok := e.cfg.Overrides.Namespaces[namespace]; ok {
		if ns.Policy != nil {
			mergePolicy(&eff, ns.Policy)
			e.m.OverridesApplied.WithLabelValues("namespace").Inc()
		}
	}

	// path-level (first match wins, in order)
	rel := filepath.ToSlash(fullPath)
	for _, p := range e.cfg.Overrides.Paths {
		if p.Policy == nil {
			continue
		}
		if matchGlobs(p.Match, rel) {
			mergePolicy(&eff, p.Policy)
			e.m.OverridesApplied.WithLabelValues("path").Inc()
			break
		}
	}
	return eff
}

func mergePolicy(base *config.PolicyConfig, o *config.PolicyConfig) {
	if o.Size != 0 {
		base.Size = o.Size
	}
	if o.Age != 0 {
		base.Age = o.Age
	}
	if o.Inactive != 0 {
		base.Inactive = o.Inactive
	}
	if o.KeepFiles != 0 {
		base.KeepFiles = o.KeepFiles
	}
	if o.KeepDays != 0 {
		base.KeepDays = o.KeepDays
	}
	if o.CompressAfter != 0 {
		base.CompressAfter = o.CompressAfter
	}
	if strings.TrimSpace(o.DefaultMode) != "" {
		base.DefaultMode = o.DefaultMode
	}
}

func matchGlobs(pattern, path string) bool {
	ok, _ := doublestar.PathMatch(pattern, path)
	return ok
}
