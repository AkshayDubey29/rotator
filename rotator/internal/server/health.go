package server

import (
	"context"
	"net/http"
	"time"

	"github.com/tapasyadubey/log-rotate-util/rotator/internal/metrics"
)

type Server struct {
	addr string
	srv  *http.Server
}

func New(addr string, m *metrics.Registry) *Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/live", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.Handle("/metrics", m.Handler())
	return &Server{addr: addr, srv: &http.Server{Addr: addr, Handler: mux}}
}

func (s *Server) Start() error { return s.srv.ListenAndServe() }

func (s *Server) Shutdown(ctx context.Context) error {
	c, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	return s.srv.Shutdown(c)
}

