variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "noc-simulator"
}

variable "vpc_cidr" {
  description = "IP range of the VPC (must be a /16)."
  type        = string
  default     = "10.50.0.0/16"
}

variable "cluster_version" {
  # Stay on a version in STANDARD support: extended support costs 6x more per hour.
  # Check with: aws eks describe-cluster-versions --query "clusterVersions[].[clusterVersion,versionStatus]"
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "api_allowed_cidrs" {
  # GitHub-hosted runners deploy from changing IPs, so the API stays reachable from the
  # internet; every request still needs valid AWS IAM credentials. A stricter setup would
  # use self-hosted runners or GitOps (Argo CD pulls from inside the cluster).
  description = "CIDRs allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  # The AWS Free plan only launches free-tier-eligible types: t3.large is rejected, m7i-flex.large works.
  description = "EC2 instance types for the worker nodes."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "node_desired_size" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "github_oidc_subject" {
  # Find it with: gh api repos/OWNER/REPO/actions/oidc/customization/sub  (sub_claim_prefix)
  description = "GitHub OIDC subject prefix of this repo, e.g. repo:owner@123/noc-simulator@456."
  type        = string
}

variable "alert_email" {
  description = "Email address that receives AWS budget alerts."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Set alert_email in terraform.tfvars to a real email address."
  }
}

variable "monthly_budget_usd" {
  description = "Budget alert threshold in USD (usage before credits)."
  type        = number
  default     = 25
}
