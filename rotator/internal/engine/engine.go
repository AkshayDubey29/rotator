package engine

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/config"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/discover"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/metrics"
	"github.com/tapasyadubey/log-rotate-util/rotator/pkg/budget"
)

type Engine struct {
	cfg  *config.Config
	m    *metrics.Registry
	log  *log.Entry
	jrnl *Journal
	bud  *budget.Tracker
}

func New(cfg *config.Config, m *metrics.Registry, logger *log.Entry) (*Engine, error) {
	j := newJournal("/var/lib/rotator/state.json")
	b := budget.New(int64(cfg.Defaults.Budgets.PerNamespaceBytes))
	return &Engine{cfg: cfg, m: m, log: logger, jrnl: j, bud: b}, nil
}

func (e *Engine) ProcessFile(ctx context.Context, f discover.FileInfo, pol config.PolicyConfig) error {
	_ = ctx
	shouldRotate := false
	if pol.Size > 0 && f.Size >= int64(pol.Size) {
		shouldRotate = true
	}
	if !shouldRotate && pol.Age > 0 {
		age := time.Since(time.UnixMilli(f.ModTimeMs))
		if age >= pol.Age {
			shouldRotate = true
		}
	}
	if !shouldRotate && pol.Inactive > 0 {
		inactive := time.Since(time.UnixMilli(f.ModTimeMs))
		if inactive >= pol.Inactive {
			shouldRotate = true
		}
	}
	if !shouldRotate {
		return nil
	}

	var target string
	var bytes int64
	var err error
	tech := pol.DefaultMode
	switch tech {
	case "copytruncate":
		target, bytes, err = rotateByCopyTruncate(f.Path)
	default:
		tech = "rename"
		target, bytes, err = rotateByRename(f.Path)
	}
	if err != nil {
		return err
	}
	e.jrnl.Record(f.Path, "rotated")
	e.m.RotationsTotal.WithLabelValues(f.Namespace, tech).Inc()
	e.m.BytesRotatedTotal.WithLabelValues(f.Namespace).Add(float64(bytes))
	e.bud.Add(f.Namespace, bytes)
	e.m.NamespaceUsageBytes.WithLabelValues(f.Namespace).Set(float64(e.bud.Get(f.Namespace)))

	if e.bud.OverLimit(f.Namespace) {
		go purgeOldestForNamespace(f.Namespace, e.cfg.Defaults.Discovery.Path, int64(e.cfg.Defaults.Budgets.PerNamespaceBytes), e.m)
	}

	if pol.CompressAfter > 0 {
		go func(path string, delay time.Duration) {
			time.Sleep(delay)
			_, _ = compressGzip(path)
		}(target, pol.CompressAfter)
	}

	_ = enforceRetention(f.Path, pol.KeepFiles, pol.KeepDays)
	return nil
}

// purgeOldestForNamespace walks the discovery path and removes oldest rotated archives for the namespace until under limit.
func purgeOldestForNamespace(namespace, root string, limit int64, m *metrics.Registry) {
	type item struct {
		path string
		size int64
		mod  int64
	}
	var items []item
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		// expect path root/<ns>/<pod>/file.log.N(.gz)
		rel, rerr := filepath.Rel(root, path)
		if rerr != nil {
			return nil
		}
		parts := strings.Split(filepath.ToSlash(rel), "/")
		if len(parts) < 3 || parts[0] != namespace {
			return nil
		}
		base := parts[len(parts)-1]
		if !strings.Contains(base, ".") {
			return nil
		}
		// treat as rotated archive
		info, ierr := d.Info()
		if ierr != nil {
			return nil
		}
		items = append(items, item{path: path, size: info.Size(), mod: info.ModTime().Unix()})
		return nil
	})
	// sort oldest first
	sort.Slice(items, func(i, j int) bool { return items[i].mod < items[j].mod })
	var total int64
	for _, it := range items {
		total += it.size
	}
	for total > limit && len(items) > 0 {
		it := items[0]
		_ = os.Remove(it.path)
		total -= it.size
		items = items[1:]
	}
}
