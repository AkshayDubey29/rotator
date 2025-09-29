package discover

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/bmatcuk/doublestar/v4"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/config"
)

type FileInfo struct {
	Path      string
	Namespace string
	Pod       string
	Size      int64
	ModTimeMs int64
}

type Engine struct {
	base      config.DiscoveryConfig
	overrides config.Overrides
}

func New(base config.DiscoveryConfig, ov config.Overrides) *Engine {
	return &Engine{base: base, overrides: ov}
}

func (e *Engine) Scan() []FileInfo {
	var out []FileInfo
	root := e.base.Path
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if depthExceeds(root, path, e.base.MaxDepth) {
				return filepath.SkipDir
			}
			return nil
		}
		// reject symlinks and ensure within root
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if !isWithinRoot(root, path) {
			return nil
		}

		rel := filepath.ToSlash(path)
		if !matchesAny(rel, e.base.Include) || matchesAny(rel, e.base.Exclude) {
			return nil
		}
		// infer namespace and pod from /pang/logs/<ns>/<pod>/...
		ns, pod := inferNSPod(root, path)
		if ns == "" || pod == "" {
			return nil
		}
		// apply namespace/path discovery overrides if present
		if !e.allowedByOverrides(ns, rel) {
			return nil
		}
		info, statErr := d.Info()
		if statErr != nil {
			return nil
		}
		out = append(out, FileInfo{
			Path:      path,
			Namespace: ns,
			Pod:       pod,
			Size:      info.Size(),
			ModTimeMs: info.ModTime().UnixMilli(),
		})
		return nil
	})
	return out
}

func (e *Engine) allowedByOverrides(namespace, rel string) bool {
	// Namespace-level discovery include/exclude
	if nsOv, ok := e.overrides.Namespaces[namespace]; ok {
		if nsOv.Discovery != nil {
			dc := nsOv.Discovery
			if len(dc.Include) > 0 && !matchesAny(rel, dc.Include) {
				return false
			}
			if len(dc.Exclude) > 0 && matchesAny(rel, dc.Exclude) {
				return false
			}
		}
	}
	// Path-level discovery include/exclude (first matching path override)
	for _, p := range e.overrides.Paths {
		if p.Discovery == nil {
			continue
		}
		if ok, _ := doublestar.PathMatch(p.Match, rel); ok {
			dc := p.Discovery
			if len(dc.Include) > 0 && !matchesAny(rel, dc.Include) {
				return false
			}
			if len(dc.Exclude) > 0 && matchesAny(rel, dc.Exclude) {
				return false
			}
			break
		}
	}
	return true
}

func depthExceeds(root, path string, max int) bool {
	if max <= 0 {
		return false
	}
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}
	if rel == "." {
		return false
	}
	parts := strings.Split(filepath.ToSlash(rel), "/")
	return len(parts) > max
}

func matchesAny(path string, patterns []string) bool {
	if len(patterns) == 0 {
		return true
	}
	for _, p := range patterns {
		if ok, _ := doublestar.PathMatch(p, path); ok {
			return true
		}
	}
	return false
}

func inferNSPod(root, full string) (string, string) {
	rel, err := filepath.Rel(root, full)
	if err != nil {
		return "", ""
	}
	parts := strings.Split(filepath.ToSlash(rel), "/")
	if len(parts) < 3 {
		return "", ""
	}
	return parts[0], parts[1]
}

func isWithinRoot(root, p string) bool {
	rel, err := filepath.Rel(root, p)
	if err != nil {
		return false
	}
	rel = filepath.ToSlash(rel)
	return !strings.HasPrefix(rel, "../") && rel != ".."
}
