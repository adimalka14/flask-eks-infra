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
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3
- [Docker](https://docs.docker.com/get-docker/)

---

## Step 1 — Provision Infrastructure with Terraform

### 1.1 Bootstrap remote state (S3 + DynamoDB)

```bash
cd terraform
terraform init
terraform apply -target=module.bootstrap
```

This creates the S3 bucket (`flask-eks-infra-tr-state`) and DynamoDB lock table used as the Terraform backend.

### 1.2 Provision all resources

```bash
terraform apply
```

Resources created:
- VPC with public and private subnets
- EKS cluster (`flask-eks-infra-cluster`, Kubernetes 1.31)
- Two EKS node groups (one per subnet)
- ECR repository for the Docker image
- IAM roles and policies

### 1.3 Key outputs

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
  --name flask-eks-infra-cluster
```

### 3.2 Deploy

```bash
ECR_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
IMAGE_TAG=$(git rev-parse --short HEAD)

helm upgrade --install flask-server ./helm/server \
  --set image.repository=$ECR_URL \
  --set image.tag=$IMAGE_TAG \
  --namespace default
```

### 3.3 Get the public endpoint

```bash
kubectl get svc flask-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open the printed URL in a browser — the app should return:
```json
{ "message": "Hello from Flask on EKS!", "version": "1.0.0", "environment": "production" }
```

---

## Step 4 — GitHub Actions (CI/CD)

Set the following secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY_URL` | output of `ecr_repository_url` |
| `EKS_CLUSTER_NAME` | `flask-eks-infra-cluster` |

On every push to `main` the workflow will:
1. Build the Docker image and push it to ECR (tagged with the commit SHA)
2. Deploy/update the Helm release on EKS

---

## Application Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Hello message with version and environment |
| `GET /health/live` | Liveness probe (used by Kubernetes) |
| `GET /health/ready` | Readiness probe (used by Kubernetes) |
| `GET /metrics` | Prometheus metrics |

---

## Teardown

```bash
helm uninstall flask-server
cd terraform && terraform destroy
```
