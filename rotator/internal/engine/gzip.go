package engine

import (
	"compress/gzip"
	"io"
)

func newGzipWriter(w io.Writer) (*gzip.Writer, error) {
	zw := gzip.NewWriter(w)
	return zw, nil
}
