package main

import (
	"context"
	"flag"
	"os/signal"
	"syscall"
	"time"

	"github.com/tapasyadubey/log-rotate-util/rotator/internal/config"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/discover"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/engine"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/metrics"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/policy"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/server"
	"github.com/tapasyadubey/log-rotate-util/rotator/internal/util"
)

func main() {
	cfgPath := flag.String("config", "/etc/rotator/config.yaml", "Path to config file")
	listen := flag.String("listen", ":9102", "Metrics and health listen address")
	flag.Parse()

	log := util.NewLogger()

	cfg, err := config.Load(*cfgPath)
	if err != nil {
		log.WithError(err).Fatal("failed to load config")
	}

	prom := metrics.NewRegistry()
	srv := server.New(*listen, prom)
	go func() {
		_ = srv.Start()
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	disc := discover.New(cfg.Defaults.Discovery, cfg.Overrides)
	pol := policy.New(cfg)
	rot, err := engine.New(cfg, prom, log)
	if err != nil {
		log.WithError(err).Fatal("failed to init engine")
	}

	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	log.Info("rotator started")
	for {
		select {
		case <-ctx.Done():
			log.Info("shutting down")
			_ = srv.Shutdown(context.Background())
			return
		case <-ticker.C:
			prom.ScanCycles.Inc()
			files := disc.Scan()
			log.WithField("files_found", len(files)).Info("scan cycle")
			for _, f := range files {
				ns := f.Namespace
				eff := pol.EffectivePolicy(ns, f.Path)
				log.WithFields(map[string]interface{}{
					"file":      f.Path,
					"namespace": ns,
					"size":      f.Size,
					"threshold": eff.Size,
				}).Debug("processing file")
				if err := rot.ProcessFile(ctx, f, eff); err != nil {
					prom.CountError("process_file")
					log.WithError(err).WithField("file", f.Path).Warn("process failed")
				}
			}
		}
	}
}
