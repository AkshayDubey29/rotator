package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type DiscoveryConfig struct {
	Path     string   `yaml:"path"`
	Include  []string `yaml:"include"`
	Exclude  []string `yaml:"exclude"`
	MaxDepth int      `yaml:"maxDepth"`
}

type PolicyConfig struct {
	Size          ByteSize      `yaml:"size"`
	Age           time.Duration `yaml:"age"`
	Inactive      time.Duration `yaml:"inactive"`
	KeepFiles     int           `yaml:"keepFiles"`
	KeepDays      int           `yaml:"keepDays"`
	CompressAfter time.Duration `yaml:"compressAfter"`
	DefaultMode   string        `yaml:"defaultMode"` // rename | copytruncate
}

type BudgetConfig struct {
	PerNamespaceBytes ByteSize `yaml:"perNamespaceBytes"`
}

type Defaults struct {
	Discovery DiscoveryConfig `yaml:"discovery"`
	Policy    PolicyConfig    `yaml:"policy"`
	Budgets   BudgetConfig    `yaml:"budgets"`
}

type NamespaceOverride struct {
	Policy    *PolicyConfig    `yaml:"policy"`
	Discovery *DiscoveryConfig `yaml:"discovery"`
	Budgets   *BudgetConfig    `yaml:"budgets"`
}

type PathOverride struct {
	Match     string           `yaml:"match"`
	Policy    *PolicyConfig    `yaml:"policy"`
	Discovery *DiscoveryConfig `yaml:"discovery"`
}

type Overrides struct {
	Namespaces map[string]NamespaceOverride `yaml:"namespaces"`
	Paths      []PathOverride               `yaml:"paths"`
}

type Config struct {
	Defaults  Defaults  `yaml:"defaults"`
	Overrides Overrides `yaml:"overrides"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var c Config
	if err := yaml.Unmarshal(data, &c); err != nil {
		return nil, err
	}
	setDefaults(&c)
	return &c, nil
}

func setDefaults(c *Config) {
	if c.Defaults.Discovery.Path == "" {
		c.Defaults.Discovery.Path = "/pang/logs"
	}
	if c.Defaults.Discovery.MaxDepth == 0 {
		c.Defaults.Discovery.MaxDepth = 8
	}
	if c.Defaults.Policy.Size == 0 {
		c.Defaults.Policy.Size = 100 * MiB
	}
	if c.Defaults.Policy.Age == 0 {
		c.Defaults.Policy.Age = 24 * time.Hour
	}
	if c.Defaults.Policy.Inactive == 0 {
		c.Defaults.Policy.Inactive = 6 * time.Hour
	}
	if c.Defaults.Policy.KeepFiles == 0 {
		c.Defaults.Policy.KeepFiles = 5
	}
	if c.Defaults.Policy.KeepDays == 0 {
		c.Defaults.Policy.KeepDays = 3
	}
	if c.Defaults.Policy.CompressAfter == 0 {
		c.Defaults.Policy.CompressAfter = time.Hour
	}
	if c.Defaults.Policy.DefaultMode == "" {
		c.Defaults.Policy.DefaultMode = "rename"
	}
	if c.Defaults.Budgets.PerNamespaceBytes == 0 {
		c.Defaults.Budgets.PerNamespaceBytes = 10 * GiB
	}
}

// ByteSize is a helper to parse human-friendly sizes from YAML
type ByteSize int64

const (
	KiB ByteSize = 1024
	MiB          = 1024 * KiB
	GiB          = 1024 * MiB
)

func (b *ByteSize) UnmarshalYAML(value *yaml.Node) error {
	var s string
	if err := value.Decode(&s); err == nil {
		parsed, err := parseSize(s)
		if err != nil {
			return err
		}
		*b = ByteSize(parsed)
		return nil
	}
	var i int64
	if err := value.Decode(&i); err == nil {
		*b = ByteSize(i)
		return nil
	}
	return fmt.Errorf("invalid size: %v", value.Value)
}

func parseSize(s string) (int64, error) {
	var n int64
	var unit string
	_, err := fmt.Sscanf(s, "%d%s", &n, &unit)
	if err != nil {
		return 0, err
	}
	switch unit {
	case "", "b", "B":
		return n, nil
	case "k", "K", "Ki", "KiB":
		return n * int64(KiB), nil
	case "m", "M", "Mi", "MiB":
		return n * int64(MiB), nil
	case "g", "G", "Gi", "GiB":
		return n * int64(GiB), nil
	default:
		return 0, fmt.Errorf("unknown unit %q", unit)
	}
}
