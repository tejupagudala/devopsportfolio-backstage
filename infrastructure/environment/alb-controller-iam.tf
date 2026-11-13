
# IAM permissions for AWS Load Balancer Controller

resource "aws_iam_policy" "alb_controller" {
  name = "${local.name}-alb-controller"

  policy = file(
    "${path.module}/policies/aws-load-balancer-controller.json"
  )
}

# EKS Pod Identity role
resource "aws_iam_role" "alb_controller" {
  name = "${local.name}-alb-controller"

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
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# Associate IAM role with Kubernetes service account
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.idp.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.alb_controller
  ]
}
