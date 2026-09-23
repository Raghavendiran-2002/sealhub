package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	Group   = "sealhub.io"
	Version = "v1alpha1"
)

type HubPullSpec struct {
	Server          string        `json:"server"`
	DocumentPath    string        `json:"documentPath"`
	Watch           *bool  `json:"watch,omitempty"`
	RefreshInterval string `json:"refreshInterval,omitempty"`
	Auth            HubPullAuth   `json:"auth"`
	Target          HubPullTarget `json:"target"`
}

type HubPullAuth struct {
	SecretRef SecretKeyRef `json:"secretRef"`
}

type SecretKeyRef struct {
	Name string `json:"name"`
	Key  string `json:"key"`
}

type HubPullTarget struct {
	Kind     string `json:"kind"`
	Template string `json:"template"`
}

type HubPullStatus struct {
	ObservedVersion int    `json:"observedVersion,omitempty"`
	LastSyncTime    string `json:"lastSyncTime,omitempty"`
	Conditions      []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

type HubPull struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              HubPullSpec   `json:"spec,omitempty"`
	Status            HubPullStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

type HubPullList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []HubPull `json:"items"`
}

func init() {
	SchemeBuilder.Register(&HubPull{}, &HubPullList{})
}
