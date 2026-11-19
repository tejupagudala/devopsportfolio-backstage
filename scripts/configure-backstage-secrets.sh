
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="us-east-1"
CLUSTER="backstage-idp"
APP_SECRET="backstage/idp/oauth"

cd "$ROOT"

echo "Checking prerequisites..."
command -v aws >/dev/null
command -v terraform >/dev/null
command -v kubectl >/dev/null
command -v python3 >/dev/null

echo "Reading current RDS Terraform outputs..."

RDS_HOST="$(terraform -chdir=infrastructure/environment output -raw rds_endpoint)"
RDS_PORT="$(terraform -chdir=infrastructure/environment output -raw rds_port)"
RDS_SECRET_ARN="$(terraform -chdir=infrastructure/environment output -raw rds_master_secret_arn)"

export RDS_HOST RDS_PORT RDS_SECRET_ARN REGION APP_SECRET

echo "Connecting to EKS..."

aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER"

kubectl get nodes >/dev/null

echo "Updating database connection settings in AWS Secrets Manager..."

python3 - <<'PY'
import json
import os
import subprocess
import tempfile
from pathlib import Path

region = os.environ["REGION"]
secret_name = os.environ["APP_SECRET"]

result = subprocess.run(
    [
        "aws", "secretsmanager", "get-secret-value",
        "--region", region,
        "--secret-id", secret_name,
        "--query", "SecretString",
        "--output", "text",
    ],
    check=True,
    capture_output=True,
    text=True,
)

data = json.loads(result.stdout)

required = [
    "GITHUB_CLIENT_ID",
    "GITHUB_CLIENT_SECRET",
    "GITHUB_TOKEN",
]

missing = [key for key in required if not data.get(key)]
if missing:
    raise SystemExit(
        "Missing GitHub credentials in AWS secret: "
        + ", ".join(missing)
    )

data["POSTGRES_HOST"] = os.environ["RDS_HOST"]
data["POSTGRES_PORT"] = str(os.environ["RDS_PORT"])

# Temporary file is private and deleted after use.
path = None
try:
    with tempfile.NamedTemporaryFile(
        mode="w",
        prefix="backstage-secret-",
        suffix=".json",
        delete=False,
    ) as f:
        path = Path(f.name)
        os.chmod(path, 0o600)
        json.dump(data, f)

    subprocess.run(
        [
            "aws", "secretsmanager", "put-secret-value",
            "--region", region,
            "--secret-id", secret_name,
            "--secret-string", f"file://{path}",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
finally:
    if path:
        path.unlink(missing_ok=True)

print("AWS secret connection settings updated.")
PY

echo "Creating Backstage namespace..."

kubectl create namespace backstage \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Installing RDS CA certificate..."

kubectl -n backstage create secret generic backstage-rds-ca \
  --from-file=rds-ca.pem=certs/rds-ca.pem \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Configuring External Secrets Operator..."

kubectl apply -f deploy/kubernetes/cluster-secret-store.yaml

# Replace the RDS ARN placeholder in memory.
sed \
  -e "s|RDS_SECRET_ARN_PLACEHOLDER|${RDS_SECRET_ARN}|g" \
  -e "s|backstage-idp-rds-secret-arn-placeholder|${RDS_SECRET_ARN}|g" \
  deploy/kubernetes/external-secrets/backstage-external-secret.yaml \
  | kubectl apply -f -

echo "Checking ExternalSecret readiness..."

kubectl wait \
  --namespace backstage \
  --for=condition=Ready \
  externalsecret/backstage-runtime \
  --timeout=180s

echo "Checking Kubernetes Secrets..."

kubectl get secret \
  backstage-runtime backstage-rds-ca \
  --namespace backstage

echo "Backstage secrets configured successfully!"
