package controller

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"text/template"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/yaml"

	sealhubv1 "github.com/raghavendiran/sealhub/operator/api/v1alpha1"
	hubclient "github.com/raghavendiran/sealhub/pkg/client"
	"github.com/raghavendiran/sealhub/pkg/document"
)

const fieldManager = "sealhub-operator"

type HubPullReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

func (r *HubPullReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	var pull sealhubv1.HubPull
	if err := r.Get(ctx, req.NamespacedName, &pull); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	tok, err := r.tokenFor(ctx, &pull)
	if err != nil {
		return ctrl.Result{}, err
	}
	c := hubclient.New(pull.Spec.Server, tok)
	env, err := c.Get(ctx, pull.Spec.DocumentPath)
	if err != nil {
		return ctrl.Result{}, err
	}
	rendered, err := renderTarget(pull.Spec.Target, env)
	if err != nil {
		return ctrl.Result{}, err
	}
	if err := r.applyRendered(ctx, &pull, rendered); err != nil {
		return ctrl.Result{}, err
	}
	pull.Status.ObservedVersion = env.Metadata.Version
	pull.Status.LastSyncTime = metav1.Now().Format(time.RFC3339)
	if err := r.Status().Update(ctx, &pull); err != nil {
		logger.Info("status update", "err", err)
	}

	interval := 5 * time.Minute
	if pull.Spec.RefreshInterval != "" {
		if d, err := time.ParseDuration(pull.Spec.RefreshInterval); err == nil {
			interval = d
		}
	}
	watch := true
	if pull.Spec.Watch != nil {
		watch = *pull.Spec.Watch
	}
	if watch && interval > 2*time.Minute {
		interval = 2 * time.Minute
	}
	return ctrl.Result{RequeueAfter: interval}, nil
}

func (r *HubPullReconciler) tokenFor(ctx context.Context, pull *sealhubv1.HubPull) (string, error) {
	var sec corev1.Secret
	key := types.NamespacedName{Namespace: pull.Namespace, Name: pull.Spec.Auth.SecretRef.Name}
	if err := r.Get(ctx, key, &sec); err != nil {
		return "", err
	}
	return string(sec.Data[pull.Spec.Auth.SecretRef.Key]), nil
}

func renderTarget(t sealhubv1.HubPullTarget, env *document.Envelope) ([]byte, error) {
	tmpl, err := template.New("target").Parse(t.Template)
	if err != nil {
		return nil, err
	}
	var docData any
	_ = json.Unmarshal([]byte(env.Document), &docData)
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, map[string]any{
		"document": env.Document,
		"data":     docData,
		"metadata": env.Metadata,
	}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func (r *HubPullReconciler) applyRendered(ctx context.Context, pull *sealhubv1.HubPull, raw []byte) error {
	kind := strings.ToLower(pull.Spec.Target.Kind)
	switch kind {
	case "secret", "secrets", "":
		var sec corev1.Secret
		if err := yaml.Unmarshal(raw, &sec); err != nil {
			return err
		}
		sec.Namespace = pull.Namespace
		if sec.Name == "" {
			sec.Name = pull.Name
		}
		existing := &corev1.Secret{}
		err := r.Get(ctx, types.NamespacedName{Namespace: sec.Namespace, Name: sec.Name}, existing)
		if apierrors.IsNotFound(err) {
			return r.Create(ctx, &sec)
		}
		if err != nil {
			return err
		}
		sec.ResourceVersion = existing.ResourceVersion
		return r.Update(ctx, &sec)
	case "configmap":
		var cm corev1.ConfigMap
		if err := yaml.Unmarshal(raw, &cm); err != nil {
			return err
		}
		cm.Namespace = pull.Namespace
		if cm.Name == "" {
			cm.Name = pull.Name
		}
		existing := &corev1.ConfigMap{}
		err := r.Get(ctx, types.NamespacedName{Namespace: cm.Namespace, Name: cm.Name}, existing)
		if apierrors.IsNotFound(err) {
			return r.Create(ctx, &cm)
		}
		if err != nil {
			return err
		}
		cm.ResourceVersion = existing.ResourceVersion
		return r.Update(ctx, &cm)
	default:
		return fmt.Errorf("unsupported kind %q", pull.Spec.Target.Kind)
	}
}

func (r *HubPullReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&sealhubv1.HubPull{}).
		WithEventFilter(predicate.GenerationChangedPredicate{}).
		Complete(r)
}
