#!/bin/bash
set -e

CLUSTER_NAME="flask-eks-infra-cluster"
BUCKET_NAME="flask-eks-infra-tr-state"
TABLE_NAME="flask-eks-infra-tr-lock"
ECR_NAME="flask-eks-infra"
REGION="us-east-1"

cd "$(dirname "$0")/../terraform"

echo "==> terraform init"
terraform init

echo ""
echo "==> Importing bootstrap resources..."

terraform import module.bootstrap.aws_s3_bucket.state "$BUCKET_NAME" || true
terraform import module.bootstrap.aws_s3_bucket_versioning.state "$BUCKET_NAME" || true
terraform import module.bootstrap.aws_s3_bucket_server_side_encryption_configuration.state "$BUCKET_NAME" || true
terraform import module.bootstrap.aws_s3_bucket_public_access_block.state "$BUCKET_NAME" || true
terraform import module.bootstrap.aws_dynamodb_table.lock "$TABLE_NAME" || true

echo ""
echo "==> Importing ECR repository..."
terraform import aws_ecr_repository.app "$ECR_NAME" || true

echo ""
echo "==> Importing KMS alias..."
terraform import 'module.eks.module.kms.aws_kms_alias.this["cluster"]' "alias/eks/$CLUSTER_NAME" || true

echo ""
echo "==> Importing CloudWatch log group..."
terraform import 'module.eks.aws_cloudwatch_log_group.this[0]' "/aws/eks/$CLUSTER_NAME/cluster" || true

echo ""
echo "==> All imports done."
echo "Run 'terraform plan' to verify state is clean before the next CI run."
