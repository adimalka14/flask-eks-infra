project_name         = "flask-eks-infra"
region               = "us-east-1"
vpc_cidr             = "10.0.0.0/16"
public_subnet_count  = 1
private_subnet_count = 1
cluster_name         = "flask-eks-infra-cluster"
cluster_version      = "1.31"
tags = {
  Environment = "dev"
  Project     = "flask-eks"
  ManagedBy   = "terraform"
}
bucket_name = "flask-eks-infra-tr-state"
table_name = "flask-eks-infra-tr-lock"
environment = "dev"
grafana_password = "password"