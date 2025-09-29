package engine

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func rotateByRename(path string) (string, int64, error) {
	// Determine next index suffix .1, .2, ... by scanning existing files
	var next int = 1
	for {
		candidate := fmt.Sprintf("%s.%d", path, next)
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			break
		}
		next++
		if next > 1000 { // safety
			return "", 0, fmt.Errorf("too many rotations for %s", path)
		}
	}
	target := fmt.Sprintf("%s.%d", path, next)
	fi, err := os.Stat(path)
	if err != nil {
		return "", 0, err
	}
	size := fi.Size()
	if err := os.Rename(path, target); err != nil {
		return "", 0, err
	}
	// recreate source file with same mode
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, fi.Mode())
	if err != nil {
		return "", 0, err
	}
	_ = f.Close()
	return target, size, nil
}

func compressGzip(src string) (string, error) {
	gz := src + ".gz"
	in, err := os.Open(src)
	if err != nil {
		return "", err
	}
	defer in.Close()
	out, err := os.Create(gz)
	if err != nil {
		return "", err
	}
	defer out.Close()
	// use stdlib writer to avoid external deps
	zw, err := newGzipWriter(out)
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(zw, in); err != nil {
		_ = zw.Close()
		return "", err
	}
	if err := zw.Close(); err != nil {
		return "", err
	}
	if err := os.Remove(src); err != nil {
		return "", err
	}
	return gz, nil
}

// enforceRetention removes files older than keepDays or exceeding keepFiles
func enforceRetention(base string, keepFiles int, keepDays int) error {
	dir := filepath.Dir(base)
	name := filepath.Base(base)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	type item struct {
		path string
		mod  time.Time
	}
	var rotated []item
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		p := filepath.Join(dir, e.Name())
		if !matchesPrefix(p, base) {
			continue
		}
		info, _ := e.Info()
		rotated = append(rotated, item{path: p, mod: info.ModTime()})
		_ = name // avoid unused if matchesPrefix changes
	}
	// remove by age
	if keepDays > 0 {
		cutoff := time.Now().Add(-time.Duration(keepDays) * 24 * time.Hour)
		for _, it := range rotated {
			if it.mod.Before(cutoff) {
				_ = os.Remove(it.path)
			}
		}
	}
	// remove by count (simple: rescan and delete oldest beyond keepFiles)
	if keepFiles > 0 {
		// refresh list
		entries, err = os.ReadDir(dir)
		if err != nil {
			return err
		}
		rotated = rotated[:0]
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			p := filepath.Join(dir, e.Name())
			if !matchesPrefix(p, base) {
				continue
			}
			info, _ := e.Info()
			rotated = append(rotated, item{path: p, mod: info.ModTime()})
		}
		// sort by modtime asc
		for i := 0; i < len(rotated); i++ {
			for j := i + 1; j < len(rotated); j++ {
				if rotated[i].mod.After(rotated[j].mod) {
					rotated[i], rotated[j] = rotated[j], rotated[i]
				}
			}
		}
		for len(rotated) > keepFiles {
			it := rotated[0]
			_ = os.Remove(it.path)
			rotated = rotated[1:]
		}
	}
	return nil
}

func matchesPrefix(path, base string) bool {
	// match files that start with base and have numeric suffix (optionally .gz)
	bp := filepath.Base(base)
	p := filepath.Base(path)
	if !strings.HasPrefix(p, bp+".") {
		return false
	}
	rest := p[len(bp)+1:]
	// strip .gz
	if strings.HasSuffix(rest, ".gz") {
		rest = rest[:len(rest)-3]
	}
	if len(rest) == 0 {
		return false
	}
	for _, r := range rest {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
