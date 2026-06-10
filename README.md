# flask-eks-infra

Flask application deployed on AWS EKS using Terraform, Helm, and GitHub Actions.

## Architecture

```
GitHub Actions
     │
     ├─► ECR (Docker image)
     │
     └─► EKS Cluster (Helm deploy)
              │
         ┌────┴────┐
     Public      Private
     Node Group  Node Group
         │
     LoadBalancer (internet-facing)
              │
         Prometheus + Grafana (monitoring namespace)
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.15
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3
- [Docker](https://docs.docker.com/get-docker/)

---

## Step 1 — Provision Infrastructure with Terraform

### 1.1 Copy and fill in variables

```bash
cp terraform/terraform.example.tfvars terraform/terraform.tfvars
# Edit terraform.tfvars with your values
```

### 1.2 Bootstrap remote state (S3 + DynamoDB)

```bash
cd terraform
terraform init
terraform apply -target=module.bootstrap
```

This creates the S3 bucket and DynamoDB lock table used as the Terraform backend.

### 1.3 Provision all resources

```bash
terraform apply
```

Resources created:
- VPC with public and private subnets
- EKS cluster (Kubernetes 1.31)
- Two EKS node groups (public + private)
- ECR repository for the Docker image
- IAM roles and policies
- Prometheus + Grafana (kube-prometheus-stack)

### 1.4 Key outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | Kubernetes API server endpoint |
| `ecr_repository_url` | ECR URL for pushing images |
| `iam_role_arn` | EKS cluster IAM role ARN |
| `vpc_id` | VPC ID |
| `region` | AWS region |

---

## Step 2 — Build & Push Docker Image

### 2.1 Authenticate Docker with ECR

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    $(terraform -chdir=terraform output -raw ecr_repository_url | cut -d'/' -f1)
```

### 2.2 Build and push

```bash
ECR_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
IMAGE_TAG=$(git rev-parse --short HEAD)

docker build -t $ECR_URL:$IMAGE_TAG -t $ECR_URL:latest ./app
docker push $ECR_URL:$IMAGE_TAG
docker push $ECR_URL:latest
```

---

## Step 3 — Deploy to EKS with Helm

### 3.1 Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(terraform -chdir=terraform output -raw cluster_name)
```

### 3.2 Deploy

```bash
ECR_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
IMAGE_TAG=$(git rev-parse --short HEAD)

helm upgrade --install flask-app ./helm/server \
  --set image.repository=$ECR_URL \
  --set image.tag=$IMAGE_TAG \
  --namespace default
```

### 3.3 Get the public endpoint

```bash
kubectl get svc flask-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open the printed URL in a browser — the app should return:
```json
{ "message": "Hello from Flask on EKS!", "version": "1.0.0", "environment": "production" }
```

---

## Step 4 — GitHub Actions (CI/CD)

### 4.1 Required Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Where to get it |
|--------|----------------|
| `AWS_ACCESS_KEY_ID` | IAM user with EKS/ECR/S3/DynamoDB permissions |
| `AWS_SECRET_ACCESS_KEY` | Same IAM user |
| `AWS_REGION` | e.g. `us-east-1` |
| `GRAFANA_PASSWORD` | Password for Grafana admin (must contain letters, not digits only) |

> **Note:** `ECR_REPOSITORY_URL` and `EKS_CLUSTER_NAME` are **not** needed as secrets — the CD pipeline reads them directly from `terraform output`.

### 4.2 Required Environment

The `cd-infra` workflow gates destructive Terraform changes (destroys) behind a manual approval.

Go to **Settings → Environments → New environment** and create one named exactly:

```
production
```

Optionally add required reviewers to enforce human approval before any `terraform destroy`.

### 4.3 Required IAM permissions

The IAM user behind the secrets needs at minimum:

- `AmazonEKSClusterPolicy` + `eks:*`
- `AmazonEC2ContainerRegistryFullAccess`
- `AmazonS3FullAccess` (Terraform state bucket)
- `AmazonDynamoDBFullAccess` (Terraform lock table)
- `IAMFullAccess` (Terraform manages IAM roles)

### 4.4 Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `ci.yaml` | PR to `main` | Builds Docker image, runs pytest, validates Terraform |
| `cd-app.yml` | Push to `main` (app/helm changes) | Builds & pushes image to ECR, deploys via Helm |
| `cd-infra.yml` | Push to `main` (terraform changes) | Runs `terraform plan`; auto-applies if no destroys, requires manual approval otherwise |

---

## Application Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Hello message with version and environment |
| `GET /health/live` | Liveness probe (used by Kubernetes) |
| `GET /health/ready` | Readiness probe (used by Kubernetes) |
| `GET /metrics` | Prometheus metrics |

---

## Monitoring

Grafana is deployed in the `monitoring` namespace via kube-prometheus-stack.

```bash
# Port-forward to access Grafana locally
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open [http://localhost:3000](http://localhost:3000) — login with `admin` and the value of `GRAFANA_PASSWORD`.

Pre-loaded dashboards:
- Node Exporter Full
- Kubernetes Pods
- Flask/Python app metrics

---

## Running Tests Locally

```bash
cd app
pip install -r requirements.txt
pytest tests/ -v
```

---

## Teardown

```bash
helm uninstall flask-app
cd terraform && terraform destroy
```
