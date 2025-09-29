package engine

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

type journalState struct {
	Version int               `json:"version"`
	Files   map[string]string `json:"files"`
}

type Journal struct {
	mu   sync.Mutex
	path string
	st   journalState
}

func newJournal(path string) *Journal {
	j := &Journal{path: path, st: journalState{Version: 1, Files: map[string]string{}}}
	_ = j.load()
	return j
}

func (j *Journal) load() error {
	b, err := os.ReadFile(j.path)
	if err != nil {
		return nil
	}
	var s journalState
	if err := json.Unmarshal(b, &s); err != nil {
		return nil
	}
	j.st = s
	return nil
}

func (j *Journal) save() error {
	_ = os.MkdirAll(filepath.Dir(j.path), 0o755)
	b, _ := json.MarshalIndent(j.st, "", "  ")
	return os.WriteFile(j.path, b, 0o644)
}

func (j *Journal) Record(path, action string) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.st.Files[path] = action
	_ = j.save()
}
