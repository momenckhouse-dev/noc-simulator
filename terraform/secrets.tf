# External Secrets Operator (ESO) runs inside EKS. It reads the database password
# from AWS Secrets Manager and writes it into a Kubernetes Secret for the console.
# ESO gets its AWS permissions through EKS Pod Identity: no access keys anywhere.

data "aws_iam_policy_document" "external_secrets_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.project_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust.json
}

# Least privilege: ESO may read ONLY the database secret, nothing else.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.db.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-db-secret"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

# "Pods using the service account external-secrets in namespace external-secrets
#  get this IAM role."
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}
