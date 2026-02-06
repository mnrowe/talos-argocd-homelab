#!/usr/bin/env bash
set -euo pipefail

# Bootstrap ArgoCD Script
# This script works around kustomize --enable-helm compatibility issues
# by using Helm directly, then letting ArgoCD self-manage

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🚀 Bootstrapping ArgoCD with sync waves..."

# Step 1: Create namespace
echo ""
echo "📦 Creating argocd namespace..."
kubectl apply -f "$ROOT_DIR/infrastructure/controllers/argocd/ns.yaml"

# Step 2: Install ArgoCD using Helm
echo ""
echo "⎈ Installing ArgoCD via Helm..."
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 9.3.0 \
  --namespace argocd \
  --values "$ROOT_DIR/infrastructure/controllers/argocd/values.yaml" \
  --wait \
  --timeout 10m

# Step 3: Wait for CRDs to be established
echo ""
echo "⏳ Waiting for ArgoCD CRDs to be established..."
kubectl wait --for condition=established --timeout=60s crd/applications.argoproj.io

# Step 4: Wait for ArgoCD server to be ready
echo ""
echo "⏳ Waiting for ArgoCD server to be available..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Step 6: Apply root application to start GitOps self-management
echo ""
echo "🔄 Deploying root application (enables self-management)..."
kubectl apply -f "$ROOT_DIR/infrastructure/controllers/argocd/root.yaml"
kubectl apply -f infrastructure/controllers/argocd/http-route.yaml


echo ""
echo "✅ ArgoCD bootstrap complete!"
echo ""
echo "📊 ArgoCD will now sync applications in this order:"
echo "   Wave 0: Cilium (networking) & Secrets"
echo "   Wave 1: Longhorn (storage), Snapshot Controller & VolSync"
echo "   Wave 2: Infrastructure (core services)"
echo "   Wave 3: Monitoring (observability)"
echo "   Wave 4: My-Apps (workloads)"
echo ""
echo "🔍 Monitor progress with:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "🌐 Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Open: https://localhost:8080"
echo ""
echo "🔑 Get admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""

