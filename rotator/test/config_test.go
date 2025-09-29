package test

import (
	"os"
	"testing"

	"gopkg.in/yaml.v3"

	"github.com/tapasyadubey/log-rotate-util/rotator/internal/config"
)

func TestDefaultsApplied(t *testing.T) {
	// write minimal yaml
	tmp, err := os.CreateTemp("", "cfg-*.yaml")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString("defaults: {}\n"); err != nil {
		t.Fatal(err)
	}
	_ = tmp.Close()

	loaded, err := config.Load(tmp.Name())
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Defaults.Discovery.Path == "" {
		t.Fatalf("expected discovery path default")
	}
	if loaded.Defaults.Policy.Size == 0 {
		t.Fatalf("expected policy size default")
	}
}

func TestByteSizeParse(t *testing.T) {
	type S struct {
		Size config.ByteSize `yaml:"size"`
	}
	var s S
	if err := yaml.Unmarshal([]byte("size: 10Mi\n"), &s); err != nil {
		t.Fatal(err)
	}
	if int64(s.Size) != 10*1024*1024 {
		t.Fatalf("expected 10MiB, got %d", s.Size)
	}
}
