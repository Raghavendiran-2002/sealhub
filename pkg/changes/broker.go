package changes

import (
	"strings"
	"sync"
	"sync/atomic"

	"github.com/raghavendiran/sealhub/pkg/document"
)

// Event describes an index change.
type Event struct {
	Revision int64              `json:"revision"`
	Type     string             `json:"type"` // upsert | delete
	Path     string             `json:"path"`
	Metadata document.Metadata  `json:"metadata,omitempty"`
}

// Broker tracks revision and fans out events.
type Broker struct {
	revision atomic.Int64
	mu       sync.RWMutex
	subs     map[chan Event]struct{}
	history  []Event
	maxHist  int
}

func NewBroker() *Broker {
	return &Broker{
		subs:    make(map[chan Event]struct{}),
		maxHist: 512,
	}
}

func (b *Broker) Revision() int64 {
	return b.revision.Load()
}

func (b *Broker) Publish(ev Event) {
	ev.Revision = b.revision.Add(1)
	b.mu.Lock()
	b.history = append(b.history, ev)
	if len(b.history) > b.maxHist {
		b.history = b.history[len(b.history)-b.maxHist:]
	}
	subs := make([]chan Event, 0, len(b.subs))
	for ch := range b.subs {
		subs = append(subs, ch)
	}
	b.mu.Unlock()
	for _, ch := range subs {
		select {
		case ch <- ev:
		default:
		}
	}
}

func (b *Broker) Subscribe(buffer int) chan Event {
	ch := make(chan Event, buffer)
	b.mu.Lock()
	b.subs[ch] = struct{}{}
	b.mu.Unlock()
	return ch
}

func (b *Broker) Unsubscribe(ch chan Event) {
	b.mu.Lock()
	delete(b.subs, ch)
	close(ch)
	b.mu.Unlock()
}

func (b *Broker) Since(rev int64, prefix string) []Event {
	b.mu.RLock()
	defer b.mu.RUnlock()
	var out []Event
	for _, ev := range b.history {
		if ev.Revision <= rev {
			continue
		}
		if prefix != "" && !hasPrefix(ev.Path, prefix) {
			continue
		}
		out = append(out, ev)
	}
	return out
}

func hasPrefix(path, prefix string) bool {
	if prefix == "" {
		return true
	}
	return path == prefix || strings.HasPrefix(path, prefix+"/")
}
