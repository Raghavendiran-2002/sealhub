package store

import (
	"sort"
	"strings"
	"sync"

	"github.com/raghavendiran/sealhub/pkg/document"
)

// DocEntry is indexed metadata for a data document.
type DocEntry struct {
	Path     string
	BlobSHA  string
	Metadata document.Metadata
}

// Index maps API paths to entries at a fixed commit.
type Index struct {
	mu      sync.RWMutex
	entries map[string]DocEntry
}

func NewIndex() *Index {
	return &Index{entries: make(map[string]DocEntry)}
}

func (idx *Index) Set(path string, e DocEntry) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.entries[path] = e
}

func (idx *Index) Delete(path string) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	delete(idx.entries, path)
}

func (idx *Index) Get(path string) (DocEntry, bool) {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	e, ok := idx.entries[path]
	return e, ok
}

func (idx *Index) List(prefix string, labelKey, labelVal string) []DocEntry {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	var out []DocEntry
	for p, e := range idx.entries {
		if prefix != "" && !strings.HasPrefix(p, prefix) {
			continue
		}
		if labelKey != "" {
			if e.Metadata.Labels[labelKey] != labelVal {
				continue
			}
		}
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out
}

func (idx *Index) Snapshot() map[string]DocEntry {
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	cp := make(map[string]DocEntry, len(idx.entries))
	for k, v := range idx.entries {
		cp[k] = v
	}
	return cp
}
