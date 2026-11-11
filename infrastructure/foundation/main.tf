
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "petclinic-terraform-state-589077667712"
    key          = "backstage/foundation.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "backstage" {
  name                 = "devopsportfolio-backstage"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Project   = "DevOpsPortfolio"
    Component = "Backstage"
    Lifecycle = "Persistent"
  }
}

resource "aws_ecr_lifecycle_policy" "backstage" {
  repository = aws_ecr_repository.backstage.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backstage.repository_url
}
