#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "${STATE_BUCKET_NAME:-}" ] || [ -z "${STATE_TABLE_NAME:-}" ]; then
  echo "❌ Error: STATE_BUCKET_NAME and STATE_TABLE_NAME environment variables must be set."
  echo "Example: export STATE_BUCKET_NAME=my-bucket STATE_TABLE_NAME=my-table"
  exit 1
fi

echo "🗑️ Uninstalling Helm releases..."
helm uninstall flask-app || true
helm uninstall monitoring -n monitoring || true

echo "☸️ Waiting for LoadBalancer to be deleted..."
kubectl wait --for=delete svc/flask-app-server --timeout=60s || true

echo "💥 Destroying Terraform infrastructure..."
cd "$ROOT_DIR/terraform"
terraform init -backend-config="bucket=${STATE_BUCKET_NAME}" -backend-config="dynamodb_table=${STATE_TABLE_NAME}" -backend-config="region=${AWS_REGION:-us-east-1}"
terraform destroy -auto-approve