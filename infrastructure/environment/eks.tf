
# ==========================================
# Backstage EKS Cluster
# ==========================================

variable "eks_public_access_cidrs" {
  description = "Trusted IP ranges allowed to access the EKS API"
  type        = list(string)
}

# IAM role assumed by the EKS control plane
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS control plane
resource "aws_eks_cluster" "idp" {
  name     = local.name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.36"

  vpc_config {
    subnet_ids = aws_subnet.private[*].id

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"

    # Initial bootstrap administrator.
    # Later we'll use dedicated access entries.
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster
  ]

  tags = {
    Name = local.name
  }
}

# ==========================================
# Worker Node IAM Role
# ==========================================

resource "aws_iam_role" "eks_nodes" {
  name = "${local.name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# Initial CNI permissions on node role.
# Later we can move this to a dedicated Pod Identity role.
resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ==========================================
# EKS Managed Node Group
# ==========================================

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.idp.name
  node_group_name = "${local.name}-system"

  node_role_arn = aws_iam_role.eks_nodes.arn

  subnet_ids = aws_subnet.private[*].id

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 30

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "platform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker,
    aws_iam_role_policy_attachment.ecr_pull,
    aws_iam_role_policy_attachment.cni
  ]

  tags = {
    Name = "${local.name}-system"
  }
}

# ==========================================
# Outputs
# ==========================================

output "eks_cluster_name" {
  value = aws_eks_cluster.idp.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.idp.endpoint
}

output "eks_node_group_name" {
  value = aws_eks_node_group.system.node_group_name
}
