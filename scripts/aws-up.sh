#!/usr/bin/env bash
# Builds the whole AWS environment and deploys the platform onto it.
#   bash scripts/aws-up.sh
# Cost while it is up: about $9-10 per day. Tear down with: bash scripts/aws-down.sh
#
# set -e: stop at the first failing command   -u: error on unset variables
# -o pipefail: a failure anywhere in a pipe (a | b) counts as a failure
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
tf() { terraform -chdir=terraform "$@"; }

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

if ! command -v helm >/dev/null; then
  echo "helm is missing - run: bash scripts/setup-wsl.sh"; exit 1
fi

step "1/5 Terraform: building VPC, EKS, RDS, ECR, IAM, Secrets Manager, budget (about 15-20 minutes)"
tf init -backend-config=backend.hcl -input=false
tf apply   # shows the plan, then waits for you to type: yes

region=$(tf output -raw region)
cluster=$(tf output -raw cluster_name)

step "2/5 Connecting kubectl to EKS"
aws eks update-kubeconfig --region "$region" --name "$cluster"
kubectl get nodes

# The database password never passes through this script: RDS keeps it in AWS Secrets
# Manager, and External Secrets Operator copies it into the cluster (k8s/overlays/aws/external-secret.yaml).
step "3/5 Installing External Secrets Operator (fetches the DB password from Secrets Manager)"
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version 2.14.0 --namespace external-secrets --create-namespace --wait

step "4/5 Telling GitHub Actions where to deploy (repo variables, no secrets)"
my_ip=$(curl -s https://checkip.amazonaws.com)
gh variable set AWS_REGION   -R "$repo" --body "$region"
gh variable set AWS_ROLE_ARN -R "$repo" --body "$(tf output -raw github_actions_role_arn)"
gh variable set ECR_REGISTRY -R "$repo" --body "$(tf output -raw ecr_registry)"
gh variable set EKS_CLUSTER  -R "$repo" --body "$cluster"
gh variable set RDS_HOST     -R "$repo" --body "$(tf output -raw rds_host)"
gh variable set DB_SECRET_ARN -R "$repo" --body "$(tf output -raw db_secret_arn)"
gh variable set ALLOWED_CIDR -R "$repo" --body "$my_ip/32"
gh variable set AWS_DEPLOY   -R "$repo" --body "true"

step "5/5 Running the pipeline: test -> build -> scan -> push to ECR -> deploy"
gh workflow run ci.yml --ref main -R "$repo"
sleep 8
run_id=$(gh run list --workflow ci.yml --event workflow_dispatch -R "$repo" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" -R "$repo" --exit-status

printf '\n\033[32mDone. Your platform on AWS (only reachable from %s):\033[0m\n' "$my_ip"
kubectl -n noc get svc noc-console grafana
echo "Open http://<EXTERNAL-IP>:8000 (console) and http://<EXTERNAL-IP>:3000 (Grafana)."
echo "New load balancers need 2-3 minutes before they answer."
printf '\033[33mREMEMBER: bash scripts/aws-down.sh when you are finished.\033[0m\n'
