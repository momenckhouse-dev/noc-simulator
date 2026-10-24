# Builds the whole AWS environment and deploys the platform onto it.
# Run from the repo folder:   .\scripts\aws-up.ps1
# Cost while it is up: about $9-10 per day. Tear down with .\scripts\aws-down.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root "terraform"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Check { if ($LASTEXITCODE -ne 0) { throw "Last command failed (exit code $LASTEXITCODE). Fix the error above and run the script again." } }

Push-Location $root
try {
    $repo = gh repo view --json nameWithOwner -q .nameWithOwner; Check

    Step "1/5 Terraform: building VPC, EKS, RDS, ECR, IAM, budget (about 15-20 minutes)"
    terraform -chdir="$tf" init -backend-config=backend.hcl -input=false; Check
    terraform -chdir="$tf" apply -input=false; Check

    $out = terraform -chdir="$tf" output -json | ConvertFrom-Json; Check
    $dbPassword = terraform -chdir="$tf" output -raw db_password; Check

    Step "2/5 Connecting kubectl to EKS"
    aws eks update-kubeconfig --region $out.region.value --name $out.cluster_name.value; Check
    kubectl get nodes; Check

    Step "3/5 Storing the database password as a Kubernetes Secret"
    kubectl create namespace noc --dry-run=client -o yaml | kubectl apply -f -; Check
    kubectl -n noc create secret generic postgres "--from-literal=POSTGRES_PASSWORD=$dbPassword" --dry-run=client -o yaml | kubectl apply -f -; Check

    Step "4/5 Telling GitHub Actions where to deploy (repo variables, no secrets)"
    $ip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
    $vars = [ordered]@{
        AWS_REGION   = $out.region.value
        AWS_ROLE_ARN = $out.github_actions_role_arn.value
        ECR_REGISTRY = $out.ecr_registry.value
        EKS_CLUSTER  = $out.cluster_name.value
        RDS_HOST     = $out.rds_host.value
        ALLOWED_CIDR = "$ip/32"
        AWS_DEPLOY   = "true"
    }
    foreach ($name in $vars.Keys) {
        gh variable set $name --body $vars[$name] -R $repo; Check
    }

    Step "5/5 Running the pipeline: test -> build -> scan -> push to ECR -> deploy"
    gh workflow run ci.yml --ref main -R $repo; Check
    Start-Sleep -Seconds 8
    $runId = gh run list --workflow ci.yml --event workflow_dispatch -R $repo --limit 1 --json databaseId --jq ".[0].databaseId"; Check
    gh run watch $runId -R $repo --exit-status; Check

    Write-Host "`nDone. Your platform on AWS (only reachable from $ip):" -ForegroundColor Green
    kubectl -n noc get svc noc-console grafana
    Write-Host "Open http://<EXTERNAL-IP>:8000 (console) and http://<EXTERNAL-IP>:3000 (Grafana)."
    Write-Host "New load balancers need 2-3 minutes before they answer."
    Write-Host "REMEMBER: .\scripts\aws-down.ps1 when you are finished." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
