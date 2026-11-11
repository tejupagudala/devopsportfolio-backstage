
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = [
        data.aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:tejupagudala@50173264/devopsportfolio-backstage@1454174530:ref:refs/heads/main"
      ]
    }
  }
}

resource "aws_iam_role" "ecr_publisher" {
  name               = "backstage-github-ecr-publisher"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      aws_ecr_repository.backstage.arn
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "backstage-ecr-push"
  role   = aws_iam_role.ecr_publisher.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

output "ecr_publisher_role_arn" {
  value = aws_iam_role.ecr_publisher.arn
}
