# EKS = Kubernetes managed by AWS. AWS runs the control plane (the "brain");
# we only provide the worker nodes (EC2 machines) where our Pods run.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes live in the private subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_allowed_cidrs
  cluster_endpoint_private_access      = true

  # Who may use kubectl: you (the IAM user running terraform) and the GitHub deploy role.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries = {
    github_deploy = {
      principal_arn = aws_iam_role.github_actions.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Control-plane logs go to CloudWatch; keep them only 3 days (cost).
  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 3

  # A KMS key costs $1/month and lingers after destroy; not needed for this lab.
  create_kms_key            = false
  cluster_encryption_config = {}

  cluster_addons = {
    coredns    = {} # DNS inside the cluster (how "postgres" resolves)
    kube-proxy = {} # makes Services work on every node
    vpc-cni = {     # gives every Pod a real VPC IP address
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    general = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      min_size       = 1
      max_size       = 3
      desired_size   = var.node_desired_size

      # Require IMDSv2 so a Pod can't steal the node's AWS credentials.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
