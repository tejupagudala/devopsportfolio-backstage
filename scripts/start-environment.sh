
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REGION="us-east-1"
ACCOUNT="589077667712"
CLUSTER="backstage-idp"
DB_INSTANCE="backstage-idp-postgres"
REPOSITORY="devopsportfolio-backstage"
DOMAIN="idp.thedevopsportfolio.online"

# Restore from a known-good snapshot.
SNAPSHOT="${RDS_SNAPSHOT_ID:-backstage-idp-backup-20261119-171722}"

for tool in aws terraform kubectl helm jq curl python3; do
  command -v "$tool" >/dev/null || {
    echo "Missing required tool: $tool"
    exit 1
  }
done

CURRENT_ACCOUNT="$(aws sts get-caller-identity \
  --query Account --output text)"

[[ "$CURRENT_ACCOUNT" == "$ACCOUNT" ]] || {
  echo "ERROR: Wrong AWS account."
  exit 1
}

echo "Checking recovery snapshot..."

STATUS="$(aws rds describe-db-snapshots \
  --db-snapshot-identifier "$SNAPSHOT" \
  --region "$REGION" \
  --query 'DBSnapshots[0].Status' --output text)"

[[ "$STATUS" == "available" ]] || {
  echo "ERROR: Snapshot is not available."
  exit 1
}

# This script is only for creating a fresh environment.
if aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" >/dev/null 2>&1; then
  echo "ERROR: RDS already exists."
  echo "Do not run rebuild automation against a live database."
  exit 1
fi

MY_IP="$(curl -4 -fsS https://checkip.amazonaws.com \
  | tr -d '\n')"

[[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "ERROR: Could not determine public IPv4 address."
  exit 1
}

echo "Snapshot: $SNAPSHOT"
echo "Allowed public IP: $MY_IP/32"

echo "Validating Terraform..."

terraform -chdir=infrastructure/environment validate

PLAN_FILE="$(mktemp /tmp/backstage-plan.XXXXXX)"
trap 'rm -f "$PLAN_FILE"' EXIT

echo "Generating Terraform plan..."

terraform -chdir=infrastructure/environment plan \
  -out="$PLAN_FILE" \
  -var="eks_public_access_cidrs=[\"$MY_IP/32\"]" \
  -var="rds_restore_snapshot_identifier=$SNAPSHOT"

echo ""
echo "Review the plan above."
echo "It must CREATE a restored RDS instance, not replace an existing one."
read -r -p "Type APPLY to proceed: " CONFIRM

[[ "$CONFIRM" == "APPLY" ]] || {
  echo "Cancelled."
  exit 0
}

echo "Provisioning AWS environment..."

terraform -chdir=infrastructure/environment apply "$PLAN_FILE"

echo "Checking restored RDS credentials..."

RDS_SECRET_ARN="$(terraform \
  -chdir=infrastructure/environment \
  output -raw rds_master_secret_arn)"

[[ -n "$RDS_SECRET_ARN" && "$RDS_SECRET_ARN" != "None" ]] || {
  echo "ERROR: Restored RDS has no managed secret ARN."
  echo "Database credential recovery must be fixed before deployment."
  exit 1
}

aws secretsmanager describe-secret \
  --region "$REGION" \
  --secret-id "$RDS_SECRET_ARN" \
  --query Name --output text >/dev/null

echo "Connecting to EKS..."

aws eks update-kubeconfig \
  --name "$CLUSTER" \
  --region "$REGION"

kubectl wait --for=condition=Ready \
  nodes --all --timeout=600s

echo "Installing platform controllers..."

bash scripts/bootstrap-platform.sh

echo "Configuring Backstage secrets..."

bash scripts/configure-backstage-secrets.sh

echo "Finding latest ECR image..."

IMAGE_TAG="$(aws ecr describe-images \
  --repository-name "$REPOSITORY" \
  --region "$REGION" \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' \
  --output text)"

[[ -n "$IMAGE_TAG" && "$IMAGE_TAG" != "None" ]] || {
  echo "ERROR: No tagged ECR image available."
  exit 1
}

ACM_ARN="$(aws acm list-certificates \
  --region "$REGION" \
  --certificate-statuses ISSUED \
  --query "CertificateSummaryList[?DomainName=='${DOMAIN}'].CertificateArn | [0]" \
  --output text)"

[[ -n "$ACM_ARN" && "$ACM_ARN" != "None" ]] || {
  echo "ERROR: Issued ACM certificate not found."
  exit 1
}

echo "Applying Backstage Argo CD Application..."

kubectl apply -f deploy/argocd/backstage-app.yaml

# Override environment-specific Helm parameters in the live
# Argo CD Application, without editing Git-tracked files.
PATCH="$(kubectl -n argocd get application backstage -o json |
  jq -c \
    --arg tag "$IMAGE_TAG" \
    --arg cidr "$MY_IP/32" \
    --arg cert "$ACM_ARN" \
    '{
      spec: {
        source: {
          helm: {
            parameters: (
              .spec.source.helm.parameters |
              map(
                if .name == "image.tag" then
                  .value = $tag
                elif .name == "ingress.allowedCidrs" then
                  .value = $cidr
                elif .name == "ingress.certificateArn" then
                  .value = $cert
                else .
                end
              )
            )
          }
        }
      }
    }')"

kubectl -n argocd patch application backstage \
  --type merge \
  -p "$PATCH"

echo "Synchronizing Argo CD..."

kubectl -n argocd patch application backstage \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

echo "Waiting for Backstage deployment..."

kubectl rollout status deployment/backstage \
  -n backstage \
  --timeout=10m

echo "Backstage image:"
kubectl get deployment backstage -n backstage \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo ""
echo "Ingress status:"
kubectl get ingress -n backstage

echo ""
echo "Retrieve ALB hostname using:"
echo "kubectl get ingress -n backstage -o wide"
echo ""
echo "Then update the GoDaddy CNAME for idp if necessary."
echo "Portal: https://$DOMAIN"
echo ""
echo "IMPORTANT: ALB DNS and HTTPS still require verification."
echo "The environment is billable while running."
