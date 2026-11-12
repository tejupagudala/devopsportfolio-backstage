
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
    key          = "backstage/environment.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "DevOpsPortfolio"
      Application = "Backstage"
      Environment = "ephemeral"
      ManagedBy   = "Terraform"
    }
  }
}
