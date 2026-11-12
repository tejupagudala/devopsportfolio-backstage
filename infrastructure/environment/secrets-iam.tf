
# ==========================================
# EKS Pod Identity for External Secrets
# ==========================================

data "aws_caller_identity" "current" {}

# Pod Identity Agent
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.idp.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.system]
}

# IAM role for External Secrets Operator
resource "aws_iam_role" "external_secrets" {
  name = "${local.name}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      Condition = {
        StringEquals = {
          "aws:RequestTag/kubernetes-namespace"       = "external-secrets"
          "aws:RequestTag/kubernetes-service-account" = "external-secrets"
        }
      }
    }]
  })
}

# Allow reading only the Backstage secrets
resource "aws_iam_role_policy" "external_secrets" {
  name = "read-backstage-secrets"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = [
        aws_db_instance.backstage.master_user_secret[0].secret_arn,
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:backstage/idp/oauth-*"
      ]
    }]
  })
}

# Associate IAM role with the ESO service account
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.idp.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}
