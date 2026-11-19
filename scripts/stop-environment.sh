
#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
CLUSTER="backstage-idp"
ACCOUNT="589077667712"
BACKUP="backstage-idp-backup-20261119-171722"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "Checking AWS account..."
CURRENT_ACCOUNT="$(aws sts get-caller-identity \
  --query Account --output text)"

if [[ "$CURRENT_ACCOUNT" != "$ACCOUNT" ]]; then
  echo "ERROR: Wrong AWS account."
  exit 1
fi

echo "Checking RDS recovery snapshot..."

SNAPSHOT_STATUS="$(aws rds describe-db-snapshots \
  --db-snapshot-identifier "$BACKUP" \
  --region "$REGION" \
  --query 'DBSnapshots[0].Status' \
  --output text)"

if [[ "$SNAPSHOT_STATUS" != "available" ]]; then
  echo "ERROR: Recovery snapshot is not available."
  exit 1
fi

echo "Recovery snapshot verified: $BACKUP"

read -r -p \
  "Type DESTROY to shut down the Backstage environment: " \
  CONFIRM

if [[ "$CONFIRM" != "DESTROY" ]]; then
  echo "Cancelled."
  exit 0
fi

echo "Connecting to EKS..."

aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER"

# Capture the current ALB hostname before removing Ingress.
ALB_DNS="$(kubectl get ingress -n backstage \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')"

ALB_ARN=""

if [[ -n "$ALB_DNS" ]]; then
  ALB_ARN="$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?DNSName=='${ALB_DNS}'].LoadBalancerArn" \
    --output text)"
fi

echo "Removing Backstage Ingress resources..."

kubectl delete ingress --all \
  --namespace backstage \
  --wait=true

# The controller must remove its AWS ALB before EKS is destroyed.
if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
  echo "Verifying AWS ALB deletion..."

  aws elbv2 wait load-balancers-deleted \
    --region "$REGION" \
    --load-balancer-arns "$ALB_ARN"
fi

echo "ALB cleanup completed."

MY_IP="$(curl -4 -fsS https://checkip.amazonaws.com \
  | tr -d '\n')"

FINAL_SNAPSHOT="backstage-idp-final-$(date -u +%Y%m%d%H%M%S)"

echo "Final RDS snapshot: $FINAL_SNAPSHOT"
echo "Destroying temporary infrastructure..."

terraform -chdir=infrastructure/environment destroy \
  -var="eks_public_access_cidrs=[\"$MY_IP/32\"]" \
  -var="rds_final_snapshot_identifier=$FINAL_SNAPSHOT"

echo "Terraform destroy command finished."
echo "Verify the final snapshot is available before relying on it."
echo "Existing recovery snapshot: $BACKUP"
echo "New final snapshot: $FINAL_SNAPSHOT"
