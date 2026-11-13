
#!/usr/bin/env bash
set -euo pipefail

# Run only after EKS has been created.
# Pin the chart versions selected during validation.
ARGO_CD_CHART_VERSION="${ARGO_CD_CHART_VERSION:-10.18.0}"
ESO_CHART_VERSION="${ESO_CHART_VERSION:-2.15.0}"

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


# ==========================================
# AWS Load Balancer Controller
# ==========================================

echo "Installing AWS Load Balancer Controller..."

ALB_CHART_VERSION="${ALB_CHART_VERSION:-1.14.0}"

helm repo add eks https://aws.github.io/eks-charts
helm repo update

VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --version "$ALB_CHART_VERSION" \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait \
  --timeout 10m

echo "Checking AWS Load Balancer Controller..."

kubectl rollout status \
  deployment/aws-load-balancer-controller \
  -n kube-system \
  --timeout=5m

