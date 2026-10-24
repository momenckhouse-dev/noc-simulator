# Deletes EVERYTHING on AWS so it stops costing money.
# Run from the repo folder:   .\scripts\aws-down.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root "terraform"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Check { if ($LASTEXITCODE -ne 0) { throw "Last command failed (exit code $LASTEXITCODE). Fix the error above and run the script again." } }

Push-Location $root
try {
    $repo = gh repo view --json nameWithOwner -q .nameWithOwner; Check

    Step "1/4 Turning off automatic deploys to AWS"
    gh variable set AWS_DEPLOY --body false -R $repo; Check

    terraform -chdir="$tf" init -backend-config=backend.hcl -input=false; Check
    $out = terraform -chdir="$tf" output -json | ConvertFrom-Json; Check

    if ($out.cluster_name) {
        # The load balancers were created by Kubernetes, not by Terraform. If we don't delete
        # them first, `terraform destroy` gets stuck on the VPC and they keep costing money.
        Step "2/4 Deleting the platform from EKS (this removes its load balancers)"
        aws eks update-kubeconfig --region $out.region.value --name $out.cluster_name.value; Check
        kubectl delete namespace noc --ignore-not-found --timeout=5m; Check

        $vpc = $out.vpc_id.value
        for ($i = 0; $i -lt 30; $i++) {
            $left = aws elbv2 describe-load-balancers --region $out.region.value --query "length(LoadBalancers[?VpcId=='$vpc'])" --output text; Check
            if ($left -eq "0") { break }
            Write-Host "  waiting for $left load balancer(s) to be deleted..."
            Start-Sleep -Seconds 10
        }
    }

    Step "3/4 Terraform destroy (about 10-15 minutes)"
    terraform -chdir="$tf" destroy -input=false; Check

    Step "4/4 Pointing kubectl back to Docker Desktop"
    if ($out.cluster_name) {
        $ctx = kubectl config get-contexts -o name | Where-Object { $_ -like "*cluster/$($out.cluster_name.value)" }
        if ($ctx) { kubectl config delete-context $ctx | Out-Null }
    }
    kubectl config use-context docker-desktop

    Write-Host "`nAll AWS resources for this project are deleted." -ForegroundColor Green
}
finally {
    Pop-Location
}
