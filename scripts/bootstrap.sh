#!/bin/bash
set -e

echo "Bootstrapping ArgoCD..."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --namespace argocd \
  --values infrastructure/argocd/values.yaml \
  --wait

kubectl wait --for condition=established --timeout=60s crd/applications.argoproj.io
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

kubectl apply -f infrastructure/argocd/root.yaml

echo "ArgoCD bootstrapped successfully!"
echo "Access UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
