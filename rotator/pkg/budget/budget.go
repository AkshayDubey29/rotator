package budget

import "sync"

type Tracker struct {
	mu    sync.Mutex
	byNS  map[string]int64
	limit int64
}

func New(limit int64) *Tracker {
	return &Tracker{byNS: map[string]int64{}, limit: limit}
}

func (t *Tracker) Add(namespace string, bytes int64) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.byNS[namespace] += bytes
}

func (t *Tracker) Get(namespace string) int64 {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.byNS[namespace]
}

func (t *Tracker) OverLimit(namespace string) bool {
	return t.Get(namespace) > t.limit
}

