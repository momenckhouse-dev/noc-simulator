output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_registry" {
  value = split("/", aws_ecr_repository.app["noc-console"].repository_url)[0]
}

output "rds_host" {
  value = aws_db_instance.db.address
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
