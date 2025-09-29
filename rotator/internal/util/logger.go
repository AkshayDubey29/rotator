package util

import (
	"os"

	log "github.com/sirupsen/logrus"
)

func NewLogger() *log.Entry {
	l := log.New()
	l.SetOutput(os.Stdout)
	l.SetFormatter(&log.JSONFormatter{})
	l.SetLevel(log.InfoLevel)
	return log.NewEntry(l)
}
