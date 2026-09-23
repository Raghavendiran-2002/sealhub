package store

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/object"
	githttp "github.com/go-git/go-git/v5/plumbing/transport/http"
	"github.com/raghavendiran/sealhub/pkg/changes"
	"github.com/raghavendiran/sealhub/pkg/crypto"
	"github.com/raghavendiran/sealhub/pkg/document"
)

// GitStore syncs a git worktree with GitHub and serves documents.
type GitStore struct {
	mu        sync.RWMutex
	repo      *git.Repository
	workDir   string
	branch    string
	pat       func() (string, error)
	keyring   *crypto.KeyRing
	index     *Index
	broker    *changes.Broker
	servedSHA plumbing.Hash
	ready     bool
}

type Options struct {
	LocalPath string
	CloneURL  string
	Branch    string
	PATFile   string
	Keyring   *crypto.KeyRing
	Broker    *changes.Broker
}

func OpenOrClone(ctx context.Context, opt Options) (*GitStore, error) {
	patFn := func() (string, error) {
		b, err := os.ReadFile(opt.PATFile)
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(b)), nil
	}
	if opt.Broker == nil {
		opt.Broker = changes.NewBroker()
	}
	gs := &GitStore{
		workDir: opt.LocalPath,
		branch:  opt.Branch,
		pat:     patFn,
		keyring: opt.Keyring,
		index:   NewIndex(),
		broker:  opt.Broker,
	}
	if err := os.MkdirAll(opt.LocalPath, 0o755); err != nil {
		return nil, err
	}
	repo, err := git.PlainOpen(opt.LocalPath)
	if err == git.ErrRepositoryNotExists {
		token, err := patFn()
		if err != nil {
			return nil, err
		}
		repo, err = git.PlainCloneContext(ctx, opt.LocalPath, false, &git.CloneOptions{
			URL: opt.CloneURL,
			Auth: &githttp.BasicAuth{
				Username: "x-access-token",
				Password: token,
			},
			ReferenceName: plumbing.NewBranchReferenceName(opt.Branch),
			SingleBranch:  true,
			Depth:         1,
		})
		if err != nil {
			return nil, fmt.Errorf("clone: %w", err)
		}
	} else if err != nil {
		return nil, err
	}
	gs.repo = repo
	if err := gs.refreshIndex(true); err != nil {
		return nil, err
	}
	gs.ready = true
	return gs, nil
}

func (gs *GitStore) Ready() bool {
	gs.mu.RLock()
	defer gs.mu.RUnlock()
	return gs.ready
}

func (gs *GitStore) Broker() *changes.Broker  { return gs.broker }
func (gs *GitStore) Keyring() *crypto.KeyRing { return gs.keyring }

func (gs *GitStore) Poll(ctx context.Context) error {
	token, err := gs.pat()
	if err != nil {
		return err
	}
	gs.mu.Lock()
	defer gs.mu.Unlock()
	_ = gs.setRemoteURL(token)
	out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "fetch", "origin", gs.branch).CombinedOutput()
	if err != nil && !strings.Contains(string(out), "Already up to date") {
		return fmt.Errorf("fetch: %w: %s", err, string(out))
	}
	mergeOut, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "merge", "--ff-only", "FETCH_HEAD").CombinedOutput()
	if err != nil && !strings.Contains(string(mergeOut), "Already up to date") {
		return fmt.Errorf("merge: %w: %s", err, string(mergeOut))
	}
	return gs.refreshIndexLocked(false)
}

func (gs *GitStore) headHash() (plumbing.Hash, error) {
	ref, err := gs.repo.Head()
	if err != nil {
		return plumbing.ZeroHash, err
	}
	return ref.Hash(), nil
}

func (gs *GitStore) refreshIndex(initial bool) error {
	gs.mu.Lock()
	defer gs.mu.Unlock()
	return gs.refreshIndexLocked(initial)
}

func (gs *GitStore) refreshIndexLocked(initial bool) error {
	sha, err := gs.headHash()
	if err != nil {
		return err
	}
	if sha == gs.servedSHA && !initial {
		return nil
	}
	old := gs.index.Snapshot()
	gs.index = NewIndex()
	commit, err := gs.repo.CommitObject(sha)
	if err != nil {
		return err
	}
	tree, err := commit.Tree()
	if err != nil {
		return err
	}
	_ = tree.Files().ForEach(func(f *object.File) error {
		if !strings.HasPrefix(f.Name, "data/") {
			return nil
		}
		apiPath := strings.TrimPrefix(f.Name, "data/")
		raw, err := f.Contents()
		if err != nil {
			return err
		}
		env, err := document.ParseEnvelope([]byte(raw))
		if err != nil {
			return nil
		}
		gs.index.Set(apiPath, DocEntry{
			Path:     apiPath,
			BlobSHA:  f.Hash.String(),
			Metadata: env.Metadata,
		})
		return nil
	})
	gs.servedSHA = sha
	newSnap := gs.index.Snapshot()
	for p, e := range newSnap {
		if _, ok := old[p]; !ok {
			gs.broker.Publish(changes.Event{Type: "upsert", Path: p, Metadata: e.Metadata})
		}
	}
	for p := range old {
		if _, ok := newSnap[p]; !ok {
			gs.broker.Publish(changes.Event{Type: "delete", Path: p})
		}
	}
	return nil
}

func (gs *GitStore) readFileAtHead(rel string) ([]byte, error) {
	sha, err := gs.headHash()
	if err != nil {
		return nil, err
	}
	return gs.readBlobAtCommit(sha, rel)
}

func (gs *GitStore) readBlobAtCommit(sha plumbing.Hash, path string) ([]byte, error) {
	commit, err := gs.repo.CommitObject(sha)
	if err != nil {
		return nil, err
	}
	tree, err := commit.Tree()
	if err != nil {
		return nil, err
	}
	f, err := tree.File(path)
	if err != nil {
		return nil, err
	}
	s, err := f.Contents()
	if err != nil {
		return nil, err
	}
	return []byte(s), nil
}

func (gs *GitStore) GetDocument(path string) (*document.Envelope, error) {
	gs.mu.RLock()
	defer gs.mu.RUnlock()
	if !gs.ready {
		return nil, fmt.Errorf("store not ready")
	}
	gitPath := document.GitPath(path)
	raw, err := gs.readFileAtHead(gitPath)
	if err != nil {
		return nil, ErrNotFound
	}
	env, err := document.ParseEnvelope(raw)
	if err != nil {
		return nil, err
	}
	if env.Metadata.Encrypted {
		plain, err := gs.keyring.Decrypt(env.Document)
		if err != nil {
			return nil, err
		}
		env.Document = string(plain)
		env.Metadata.Encrypted = false
	}
	return env, nil
}

func (gs *GitStore) List(prefix, labelKey, labelVal string) []DocEntry {
	return gs.index.List(prefix, labelKey, labelVal)
}

func (gs *GitStore) Apply(ctx context.Context, path, body, contentType string, encrypt bool, expectedVersion int, owner string) (*document.Envelope, error) {
	gitPath := document.GitPath(path)
	gs.mu.Lock()
	defer gs.mu.Unlock()

	var version = 1
	if raw, err := gs.readFileAtHead(gitPath); err == nil {
		existing, err := document.ParseEnvelope(raw)
		if err != nil {
			return nil, err
		}
		if expectedVersion > 0 && existing.Metadata.Version != expectedVersion {
			return nil, ErrConflict
		}
		version = existing.Metadata.Version + 1
	} else if expectedVersion > 1 {
		return nil, ErrConflict
	}

	if contentType == "" {
		contentType = "application/yaml"
	}
	docBody := body
	if encrypt {
		ct, err := gs.keyring.Encrypt([]byte(body))
		if err != nil {
			return nil, err
		}
		docBody = ct
	}
	env := &document.Envelope{
		Metadata: document.Metadata{
			Version:     version,
			ContentType: contentType,
			Encrypted:   encrypt,
			Owner:       owner,
		},
		Document: docBody,
	}
	raw, err := env.Marshal()
	if err != nil {
		return nil, err
	}
	abs := filepath.Join(gs.workDir, gitPath)
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(abs, raw, 0o644); err != nil {
		return nil, err
	}
	token, err := gs.pat()
	if err != nil {
		return nil, err
	}
	_ = gs.setRemoteURL(token)
	if out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "add", gitPath).CombinedOutput(); err != nil {
		return nil, fmt.Errorf("git add: %w: %s", err, string(out))
	}
	msg := fmt.Sprintf("sealhub: apply %s", path)
	if out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "commit", "-m", msg).CombinedOutput(); err != nil {
		if !strings.Contains(string(out), "nothing to commit") {
			return nil, fmt.Errorf("git commit: %w: %s", err, string(out))
		}
	}
	if out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "push", "origin", "HEAD:"+gs.branch).CombinedOutput(); err != nil {
		return nil, fmt.Errorf("git push: %w: %s", err, string(out))
	}
	if err := gs.refreshIndexLocked(false); err != nil {
		return nil, err
	}
	out := *env
	if encrypt {
		out.Document = body
		out.Metadata.Encrypted = false
	}
	return &out, nil
}

func (gs *GitStore) Delete(ctx context.Context, path string, expectedVersion int) error {
	gitPath := document.GitPath(path)
	gs.mu.Lock()
	defer gs.mu.Unlock()
	raw, err := gs.readFileAtHead(gitPath)
	if err != nil {
		return ErrNotFound
	}
	existing, err := document.ParseEnvelope(raw)
	if err != nil {
		return err
	}
	if expectedVersion > 0 && existing.Metadata.Version != expectedVersion {
		return ErrConflict
	}
	token, err := gs.pat()
	if err != nil {
		return err
	}
	_ = gs.setRemoteURL(token)
	if out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "rm", gitPath).CombinedOutput(); err != nil {
		return fmt.Errorf("git rm: %w: %s", err, string(out))
	}
	msg := fmt.Sprintf("sealhub: delete %s", path)
	if out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "commit", "-m", msg).CombinedOutput(); err != nil {
		return fmt.Errorf("git commit: %w: %s", err, string(out))
	}
	if out, err := exec.CommandContext(ctx, "git", "-C", gs.workDir, "push", "origin", "HEAD:"+gs.branch).CombinedOutput(); err != nil {
		return fmt.Errorf("git push: %w: %s", err, string(out))
	}
	return gs.refreshIndexLocked(false)
}

func (gs *GitStore) ReadSystemFile(relpath string) ([]byte, error) {
	gs.mu.RLock()
	defer gs.mu.RUnlock()
	return gs.readFileAtHead(relpath)
}

func (gs *GitStore) setRemoteURL(token string) error {
	cfg, err := gs.repo.Config()
	if err != nil || cfg.Remotes["origin"] == nil || len(cfg.Remotes["origin"].URLs) == 0 {
		return nil
	}
	url := cfg.Remotes["origin"].URLs[0]
	if strings.Contains(url, "x-access-token:") {
		// strip old token
		url = strings.Split(url, "@")[1]
		url = "https://" + url
	}
	if strings.HasPrefix(url, "https://") && token != "" {
		url = strings.Replace(url, "https://", "https://x-access-token:"+token+"@", 1)
	}
	_, err = exec.Command("git", "-C", gs.workDir, "remote", "set-url", "origin", url).Output()
	return err
}

var (
	ErrNotFound = fmt.Errorf("not found")
	ErrConflict = fmt.Errorf("version conflict")
)
