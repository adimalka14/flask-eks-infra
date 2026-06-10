#!/bin/bash
set -euo pipefail

cd ../terraform

echo "terraform init..."
terraform init

echo "terraform apply..."
terraform apply -auto-approve

echo "📤 Getting Terraform outputs..."
ECR_URL=$(terraform output -raw ecr_repository_url)
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

echo "☸️ Updating kubeconfig..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

echo "🚀 Deploying with Helm..."
cd ../helm
helm upgrade --install flask-app ./server \
  --set image.repository=$ECR_URL \
  --set image.tag=${IMAGE_TAG:-latest} \
  --wait \
  --timeout 5m

echo "✅ Done!"