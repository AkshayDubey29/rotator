package test

import (
	"testing"

	"github.com/tapasyadubey/log-rotate-util/rotator/internal/config"
	pol "github.com/tapasyadubey/log-rotate-util/rotator/internal/policy"
)

func TestEffectivePolicy_MergeOrder(t *testing.T) {
	cfg := &config.Config{
		Defaults: config.Defaults{
			Policy: config.PolicyConfig{Size: 100 * config.MiB, DefaultMode: "rename"},
		},
		Overrides: config.Overrides{
			Namespaces: map[string]config.NamespaceOverride{
				"payments": {Policy: &config.PolicyConfig{Size: 50 * config.MiB, DefaultMode: "copytruncate"}},
			},
			Paths: []config.PathOverride{
				{Match: "/pang/logs/legacy-service/**", Policy: &config.PolicyConfig{Size: 200 * config.MiB}},
			},
		},
	}
	e := pol.New(cfg)
	// path override should apply after namespace; size becomes 200Mi, defaultMode remains copytruncate
	eff := e.EffectivePolicy("payments", "/pang/logs/legacy-service/payments/pod/file.log")
	if eff.Size != 200*config.MiB {
		t.Fatalf("expected size 200Mi, got %d", eff.Size)
	}
	if eff.DefaultMode != "copytruncate" {
		t.Fatalf("expected copytruncate, got %s", eff.DefaultMode)
	}
}
