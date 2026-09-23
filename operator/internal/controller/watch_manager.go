package controller

import (
	"context"
	"strings"
	"sync"

	"sigs.k8s.io/controller-runtime/pkg/client"

	sealhubv1 "github.com/raghavendiran/sealhub/operator/api/v1alpha1"
	"github.com/raghavendiran/sealhub/pkg/changes"
	hubclient "github.com/raghavendiran/sealhub/pkg/client"
)

// WatchManager runs one SSE stream per HubPull when enabled.
type WatchManager struct {
	mu      sync.Mutex
	cancel  map[string]context.CancelFunc
	Client  client.Client
	Reconcile func(ctx context.Context, pull *sealhubv1.HubPull) error
}

func (w *WatchManager) Sync(ctx context.Context, pull *sealhubv1.HubPull, token string) {
	key := pull.Namespace + "/" + pull.Name
	watch := true
	if pull.Spec.Watch != nil {
		watch = *pull.Spec.Watch
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if !watch {
		if c, ok := w.cancel[key]; ok {
			c()
			delete(w.cancel, key)
		}
		return
	}
	if w.cancel == nil {
		w.cancel = make(map[string]context.CancelFunc)
	}
	if _, ok := w.cancel[key]; ok {
		return
	}
	runCtx, cancel := context.WithCancel(ctx)
	w.cancel[key] = cancel
	go func() {
		c := hubclient.New(pull.Spec.Server, token)
		prefix := pull.Spec.DocumentPath
		if i := strings.LastIndex(prefix, "/"); i >= 0 {
			prefix = prefix[:i]
		}
		_ = c.Watch(runCtx, 0, prefix, func(ev changes.Event) error {
			if ev.Path != pull.Spec.DocumentPath {
				return nil
			}
			return w.Reconcile(runCtx, pull)
		})
	}()
}
