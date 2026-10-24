# The VPC is our private network in AWS - the cloud version of the network a NOC watches.
#
#   Internet
#      │
#   Internet Gateway
#      │
#   public subnets  (2 AZs)  ── load balancers, NAT gateway
#      │  NAT (lets private machines reach out, nobody can reach in)
#   private subnets (2 AZs)  ── Kubernetes nodes, RDS database
#
# 2 Availability Zones (separate data centers) so one AZ failing doesn't take us down.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  cluster_name = "${var.project_name}-eks"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # 10.50.0.0/20 and 10.50.16.0/20 (4096 IPs each: every Pod gets a VPC IP)
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  # 10.50.48.0/24 and 10.50.49.0/24
  public_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  # ONE NAT gateway instead of one per AZ: cheaper, fine for a lab.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs record every connection (source, destination, port, ACCEPT/REJECT).
  # Real NOCs use them to troubleshoot "why can't A talk to B?".
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 3

  # Tags tell Kubernetes where it may create load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}
