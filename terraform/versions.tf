# Terraform = "infrastructure as code". Instead of clicking in the AWS console, we
# describe the network, cluster and database in files. `terraform apply` builds it,
# `terraform destroy` deletes ALL of it - that is how we keep the AWS bill tiny.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Terraform remembers what it built in a "state" file. We keep it in S3 (not on the
  # laptop) so it is safe and could be shared. Settings come from backend.hcl.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Every resource gets these tags, so you can find (and cost-track) the whole project.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
