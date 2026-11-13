
#!/usr/bin/env bash
set -euo pipefail

# Run only after EKS has been created.
# Pin the chart versions selected during validation.
: "${ARGO_CD_CHART_VERSION:?Set ARGO_CD_CHART_VERSION}"
: "${ESO_CHART_VERSION:?Set ESO_CHART_VERSION}"

CLUSTER_NAME="backstage-idp"
AWS_REGION="us-east-1"

echo "Checking AWS identity..."
aws sts get-caller-identity

echo "Connecting kubectl to EKS..."
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"

echo "Checking Kubernetes connection..."
kubectl cluster-info

echo "Adding Helm repositories..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

echo "Installing Argo CD..."
helm upgrade --install argocd argo/argo-cd \
  --version "$ARGO_CD_CHART_VERSION" \
  --namespace argocd \
  --create-namespace \
  --wait \
  --timeout 10m

echo "Installing External Secrets Operator..."
helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  --version "$ESO_CHART_VERSION" \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets \
  --wait \
  --timeout 10m

echo "Checking platform pods..."
kubectl get pods -n argocd
kubectl get pods -n external-secrets

echo "Platform bootstrap complete."
