# Talos ArgoCD Homelab

GitOps-managed Kubernetes homelab running on Talos Linux with ArgoCD, Cilium, and Gateway API.

## 🏗️ Architecture

- **OS**: Talos Linux (immutable Kubernetes OS)
- **CNI**: Cilium with Gateway API and L2 announcements
- **GitOps**: ArgoCD with SOPS encryption
- **Ingress**: Cilium Gateway API (replaces traditional ingress controllers)
- **Certificates**: cert-manager with Cloudflare DNS-01 challenge
- **Secrets**: SOPS with age encryption

## 🌐 Network Setup

- **Cluster VLAN**: <your-cluster-subnet> (e.g., 192.168.1.0/24)
- **LoadBalancer IP**: <your-loadbalancer-ip> (from your IP pool)
- **Domain**: *.<your-domain> (wildcard TLS certificate)
- **Access**: https://argocd.<your-domain>

## 📋 Prerequisites

- Talos cluster provisioned and accessible
- `kubectl` configured with cluster access
- `talosctl` installed
- `sops` and `age` for secrets management
- Cloudflare API token for DNS challenges

## 🚀 Bootstrap

### 1. Install Cilium CNI

```bash
cilium install \
  --set cluster.name=<your-cluster-name> \
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

### 2. Set up SOPS encryption

Generate age key:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Get the public key and update `.sops.yaml`:
```bash
age-keygen -y ~/.config/sops/age/keys.txt
```

Create SOPS secret for ArgoCD:
```bash
kubectl create secret generic sops-age \
  --namespace=argocd \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt
```

### 3. Bootstrap ArgoCD

```bash
./scripts/bootstrap.sh
```

Or manually:
```bash
kubectl create namespace argocd
kubectl apply -k infrastructure/controllers/argocd/
kubectl apply -f infrastructure/controllers/argocd/apps/root.yaml
```

### 4. Configure secrets

Encrypt Cloudflare API token:
```bash
# Create plaintext secret
cat > infrastructure/controllers/cert-manager/cloudflare-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
stringData:
  api-token: <your-cloudflare-api-token>
EOF

# Encrypt with SOPS
sops -e -i infrastructure/controllers/cert-manager/cloudflare-secret.yaml
```

### 5. Access ArgoCD

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Access at: https://argocd.<your-domain>

## 📁 Repository Structure

```
infrastructure/
├── controllers/
│   ├── argocd/           # ArgoCD installation & apps
│   │   ├── apps/         # ApplicationSets
│   │   ├── charts/       # Helm charts
│   │   └── values.yaml   # ArgoCD config with SOPS support
│   └── cert-manager/     # Certificate management
│       ├── cluster-issuer.yaml
│       └── cloudflare-secret.yaml (SOPS encrypted)
└── networking/
    ├── cilium/           # Cilium CNI configuration
    │   ├── values.yaml   # Cilium Helm values
    │   ├── ip-pool.yaml  # LoadBalancer IP pool
    │   ├── l2-policy.yaml # L2 announcement policy
    │   └── l2-rbac.yaml  # L2 announcer permissions
    └── gateway/          # Gateway API resources
        ├── gw-internal.yaml  # Gateway definition
        └── certificate.yaml  # Wildcard TLS cert
```

## 🔐 Security

### Pre-commit Hook

A git pre-commit hook is installed to prevent committing plaintext secrets:
- Blocks passwords, API keys, tokens (20+ chars)
- Blocks private keys
- Blocks AWS/GitHub tokens
- Allows SOPS-encrypted secrets

### Secrets Management

All secrets are encrypted with SOPS using age encryption:
```bash
# Encrypt a file
sops -e -i path/to/secret.yaml

# Decrypt for viewing
sops -d path/to/secret.yaml

# Edit encrypted file
sops path/to/secret.yaml
```

## 🔧 Common Tasks

### Update ArgoCD password
```bash
# Via UI: User Icon → User Info → Update Password
# Or via CLI:
argocd login argocd.<your-domain>
argocd account update-password
```

### Force sync an application
```bash
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Check Cilium L2 announcements
```bash
# Check lease
kubectl get lease -n kube-system | grep l2announce

# Check service IP
kubectl get svc -n gateway cilium-gateway-gateway-internal
```

### View certificates
```bash
kubectl get certificate -A
kubectl describe certificate -n <namespace> <certificate-name>
```

## 🐛 Troubleshooting

### LoadBalancer IP not accessible
- L2 announcements work at Layer 2 (same VLAN only)
- For cross-VLAN access, configure static route on router
- Ping may not work (ICMP not handled), but HTTP/HTTPS will

### ArgoCD sync issues
```bash
# Check application status
kubectl get applications -n argocd

# View sync errors
kubectl describe application <app-name> -n argocd

# Force refresh
kubectl delete application <app-name> -n argocd
# ArgoCD will recreate it automatically
```

### Certificate issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager

# Check challenges
kubectl get challenge -A

# Check orders
kubectl get order -A
```

## 📚 References

- [Talos Linux](https://www.talos.dev/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [Cilium](https://cilium.io/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [SOPS](https://github.com/getsops/sops)
- [cert-manager](https://cert-manager.io/)
