terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.15"
}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}


module "vpc" {
  source               = "./modules/vpc"
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_count  = var.public_subnet_count
  private_subnet_count = var.private_subnet_count
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids               = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  control_plane_subnet_ids = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  endpoint_public_access  = true
  endpoint_private_access = true
  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled = false
  }

  eks_managed_node_groups = {

    private_node_group = {
      subnet_ids     = module.vpc.private_subnet_ids
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      labels = {
        role = "private"
      }
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }

    public_node_group = {
      subnet_ids     = module.vpc.public_subnet_ids
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      labels = {
        role = "public"
      }
    }
  }

  addons = {
    eks-pod-identity-agent = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true  # Must install BEFORE nodes - fixes NodeCreationFailure
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }
}



module "bootstrap" {
  source = "./modules/bootstrap"
  bucket_name = var.bucket_name
  table_name = var.table_name
  environment = var.environment
}

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version = "86.2.0"

  wait          = true
  wait_for_jobs = true
  atomic        = true
  timeout       = 600

  values = [file("${path.module}/monitoring-values.yaml")]

  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = tostring(var.grafana_password)
    }
  ]

  depends_on = [module.eks]
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name                          = "aws-ebs-csi"
  attach_aws_ebs_csi_policy     = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = var.tags
}