#!/usr/bin/env bash
# Deletes EVERYTHING on AWS so it stops costing money.
#   bash scripts/aws-down.sh
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
tf() { terraform -chdir=terraform "$@"; }

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

step "1/4 Turning off automatic deploys to AWS"
gh variable set AWS_DEPLOY -R "$repo" --body false

tf init -backend-config=backend.hcl -input=false >/dev/null
cluster=$(tf output -raw cluster_name 2>/dev/null || true)

if [ -n "$cluster" ]; then
  region=$(tf output -raw region)
  vpc=$(tf output -raw vpc_id)

  # The load balancers were created by Kubernetes, not by Terraform. If we don't delete
  # them first, `terraform destroy` gets stuck on the VPC and they keep costing money.
  step "2/4 Deleting the platform from EKS (this removes its load balancers)"
  aws eks update-kubeconfig --region "$region" --name "$cluster"
  kubectl delete namespace noc --ignore-not-found --timeout=5m

  for _ in $(seq 30); do
    left=$(aws elbv2 describe-load-balancers --region "$region" \
      --query "length(LoadBalancers[?VpcId=='$vpc'])" --output text)
    [ "$left" = "0" ] && break
    echo "  waiting for $left load balancer(s) to be deleted..."
    sleep 10
  done
else
  echo "No cluster in the Terraform state - skipping the Kubernetes cleanup."
fi

step "3/4 Terraform destroy (about 10-15 minutes)"
tf destroy   # shows what will be deleted, then waits for: yes

step "4/4 Removing the deleted cluster from kubectl"
if [ -n "$cluster" ]; then
  ctx=$(kubectl config get-contexts -o name | grep "cluster/$cluster$" || true)
  [ -n "$ctx" ] && kubectl config delete-context "$ctx" >/dev/null
fi

printf '\n\033[32mAll AWS resources for this project are deleted.\033[0m\n'
