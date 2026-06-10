#!/bin/bash
set -euo pipefail

cd ../terraform

if [ -z "${STATE_BUCKET_NAME:-}" ] || [ -z "${STATE_TABLE_NAME:-}" ]; then
  echo "❌ Error: STATE_BUCKET_NAME and STATE_TABLE_NAME environment variables must be set."
  echo "Example: export STATE_BUCKET_NAME=my-bucket STATE_TABLE_NAME=my-table"
  exit 1
fi

echo "terraform init..."
terraform init -backend-config="bucket=${STATE_BUCKET_NAME}" -backend-config="dynamodb_table=${STATE_TABLE_NAME}" -backend-config="region=${AWS_REGION:-us-east-1}"

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