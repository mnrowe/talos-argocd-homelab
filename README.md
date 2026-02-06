# Talos ArgoCD Homelab

Minimal GitOps setup for Talos Kubernetes cluster with ArgoCD and Cilium.

## Prerequisites

1. Talos cluster provisioned and accessible
2. `kubectl` configured with cluster access
3. `cilium` CLI installed

## Bootstrap

### 1. Install Cilium CNI

```bash
cilium install \
  --set cluster.name=talos-homelab \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445
```

Verify:
```bash
cilium status
```

### 2. Bootstrap ArgoCD

```bash
./scripts/bootstrap.sh
```

Or manually:
```bash
kubectl create namespace argocd
helm install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --namespace argocd \
  --values infrastructure/argocd/values.yaml
kubectl apply -f infrastructure/argocd/root.yaml
```

### 3. Access ArgoCD

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Get password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Structure

```
infrastructure/
├── argocd/          # ArgoCD installation & root app
└── cilium/          # Cilium CNI configuration
```
