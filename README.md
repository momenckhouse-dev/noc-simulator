# NOC Simulator

A training platform that simulates a real Network Operations Center: fake network devices
report health metrics, Prometheus detects problems, Alertmanager routes alerts, and operators
handle them in a NOC Console (acknowledge, open incidents, write notes) while watching Grafana.

Built as a cloud / DevOps portfolio project: Docker, Kubernetes, CI/CD with GitHub Actions,
and AWS infrastructure with Terraform.

## Architecture

```
 device-simulator ──/metrics──▶ Prometheus ──alerts──▶ Alertmanager ──webhook──▶ noc-console ──▶ PostgreSQL
  (6 fake devices)               │  (alert rules)                                 (alerts, incidents,
         ▲                       ▼                                                  operator UI)
         └── lab: inject faults ─ Grafana (dashboards)   ◀── operator watches ──────────┘
```

| Component | What it does | Port (local) |
|---|---|---|
| `apps/device-simulator` | 6 routers/switches/firewall/server; exposes Prometheus metrics; fault injection API | 8001 |
| `apps/noc-console` | Receives alerts, stores them in PostgreSQL, web UI for NOC operators | 8000 |
| Prometheus | Scrapes metrics every 10s, evaluates alert rules | 9090 |
| Alertmanager | Groups alerts and sends them to the console | 9093 |
| Grafana | "NOC Overview" dashboard | 3000 |
| PostgreSQL | Alert and incident database | - |

## Run it locally

Needs Docker Desktop.

```bash
docker compose up --build
```

Then open:
- NOC Console: http://localhost:8000
- Grafana: http://localhost:3000
- Prometheus alerts: http://localhost:9090/alerts
- API docs: http://localhost:8000/docs and http://localhost:8001/docs

Break something: in the console's **Lab control** box pick a device and a fault, click
**Inject fault**, and watch the alert appear about 30-60 seconds later.

Stop everything: `docker compose down` (add `-v` to also delete the database).

## Run it on Kubernetes (Docker Desktop)

Enable Kubernetes in Docker Desktop (Settings → Kubernetes, cluster type **kubeadm**), then:

```bash
kubectl config use-context docker-desktop
docker compose down                       # free ports 8000/3000/9090

docker build -t noc-console:dev apps/noc-console
docker build -t device-simulator:dev apps/device-simulator

cp k8s/overlays/local/postgres.env.example k8s/overlays/local/postgres.env   # then set a password
kubectl apply -k k8s/overlays/local
kubectl get pods -n noc --watch
```

Same URLs as above. Remove everything: `kubectl delete -k k8s/overlays/local`.

```
k8s/
  base/                 # same everywhere: Deployments, StatefulSet, Services, probes
  overlays/local/       # Docker Desktop: local images, LoadBalancer on localhost, Secret
  overlays/aws/         # (Phase 2) ECR images, RDS, Ingress
monitoring/kustomization.yaml   # turns the monitoring config files into ConfigMaps
```

## Run it on AWS

```
                        GitHub Actions ──OIDC (no stored keys)──▶ IAM role
                          │ push image                               │ deploy
                          ▼                                          ▼
 your IP only ──▶ NLB ──▶ ┌──────────── VPC 10.50.0.0/16, 2 AZs ─────────────┐
                          │ public subnets:  NAT gateway, load balancers     │
                          │ private subnets: EKS nodes (m7i-flex.large x2)   │
                          │                  RDS PostgreSQL (db.t4g.micro)   │
                          └───────────────────────────────────────────────────┘
                          ECR (images, scan on push)   CloudWatch (EKS logs, VPC Flow Logs)   Budget alert
```

| Piece | Terraform file |
|---|---|
| VPC, subnets, NAT, flow logs | `terraform/vpc.tf` |
| EKS cluster + node group | `terraform/eks.tf` |
| RDS PostgreSQL | `terraform/rds.tf` |
| ECR repositories | `terraform/ecr.tf` |
| GitHub OIDC role | `terraform/github_oidc.tf` |
| Budget alert | `terraform/budget.tf` |

Setup once: copy `terraform/backend.hcl.example` → `backend.hcl` and `terraform/terraform.tfvars.example` → `terraform.tfvars`, fill them in.

```powershell
.\scripts\aws-up.ps1     # terraform apply, Secret, GitHub variables, run pipeline (~25 min)
.\scripts\aws-down.ps1   # delete load balancers, terraform destroy (~15 min)
```

About $9-10 per day while it is up (EKS control plane, 2 nodes, NAT gateway, 2 NLBs).
While the repo variable `AWS_DEPLOY` is `true`, every push to `main` is deployed to EKS automatically.

## Run the tests

```bash
cd apps/noc-console        # or apps/device-simulator
python -m venv .venv
.venv/Scripts/activate     # Linux/macOS: source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

## Alert rules

| Alert | Condition | Severity |
|---|---|---|
| DeviceDown | device not responding for 30s | critical |
| InterfaceDown | interface down for 30s (not when the whole device is down) | major |
| HighLatency | latency > 200 ms for 1m | major |
| PacketLoss | loss > 5% for 1m (not when the device is down) | major |
| HighCPU | CPU > 90% for 1m | minor |
| MonitoringTargetDown | Prometheus cannot scrape a service for 1m | critical |

## Roadmap

- [x] Phase 1.1: apps, Dockerfiles, Docker Compose, monitoring stack, tests
- [x] Phase 1.2: Kubernetes manifests with Kustomize (Deployments, StatefulSet, Services, ConfigMaps, Secrets, probes)
- [x] Phase 1.3: CI/CD with GitHub Actions (tests, promtool/amtool/kubeconform validation, build + push images to GHCR)
- [x] Phase 2: AWS with Terraform (VPC, EKS, RDS, ECR, OIDC, budget), Trivy scan, deploy from the pipeline
- [ ] Phase 3: troubleshooting terminal (ping, traceroute, show interfaces, show log), runbooks, escalation, training scenarios
