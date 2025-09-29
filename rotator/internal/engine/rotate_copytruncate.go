package engine

import (
	"fmt"
	"io"
	"os"
)

func rotateByCopyTruncate(path string) (string, int64, error) {
	// copy to next available suffix, then truncate original
	var next int = 1
	for {
		candidate := fmt.Sprintf("%s.%d", path, next)
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			break
		}
		next++
		if next > 1000 {
			return "", 0, fmt.Errorf("too many rotations for %s", path)
		}
	}
	target := fmt.Sprintf("%s.%d", path, next)
	in, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer in.Close()
	fi, err := in.Stat()
	if err != nil {
		return "", 0, err
	}
	out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, fi.Mode())
	if err != nil {
		return "", 0, err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return "", 0, err
	}
	_ = out.Close()
	// truncate source
	if err := os.Truncate(path, 0); err != nil {
		return "", 0, err
	}
	return target, fi.Size(), nil
}
