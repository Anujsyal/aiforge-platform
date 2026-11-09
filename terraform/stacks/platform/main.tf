# AIForge platform stack: VPC → k3s cluster → ECR → GitHub OIDC → Budgets → Crossplane IAM.
# Ek hi stack (ek hi environment). Project 2 mein dev/staging/prod the; yahan focus
# multi-TEAM self-service pe hai (teams = namespaces), multi-env pe nahi.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # Values backend.hcl se aate hain: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project    = "aiforge" # Budgets + Cost Explorer showback isi tag se
      ManagedBy  = "terraform"
      Stack      = "platform"
      CostCenter = "platform-team"
    }
  }
}

locals {
  name = var.cluster_name
}

module "vpc" {
  source = "../../modules/vpc"

  name                    = local.name
  region                  = var.region
  cluster_name            = var.cluster_name
  vpc_cidr                = var.vpc_cidr
  az_count                = 2
  single_nat_gateway      = true
  interface_endpoints     = var.interface_endpoints
  flow_log_traffic_type   = var.flow_log_traffic_type
  flow_log_retention_days = 7
}

module "cluster" {
  source = "../../modules/k3s-cluster"

  name                   = var.cluster_name
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  server_subnet_id       = module.vpc.private_subnet_ids[0]
  server_subnet_cidr     = module.vpc.private_subnet_cidrs[0]
  agent_subnet_ids       = module.vpc.private_subnet_ids
  k3s_version            = var.k3s_version
  alb_controller_version = var.alb_controller_version
  server_instance_type   = var.server_instance_type
  agent_instance_type    = var.agent_instance_type
  agent_count            = var.agent_count
  agents_use_spot        = var.agents_use_spot
}

module "ecr" {
  source       = "../../modules/ecr"
  prefix       = "aiforge"
  repositories = ["rag-app", "backstage"]
}

module "github_oidc" {
  source               = "../../modules/github-oidc"
  name                 = local.name
  github_repo          = var.github_repo
  github_owner_id      = var.github_owner_id
  github_repo_id       = var.github_repo_id
  ecr_repository_arns  = module.ecr.repository_arns
  create_oidc_provider = var.create_github_oidc_provider
}

module "budgets" {
  source                    = "../../modules/budgets"
  name                      = local.name
  alert_emails              = var.alert_emails
  account_monthly_limit_usd = var.account_monthly_limit_usd
  project_monthly_limit_usd = var.project_monthly_limit_usd
}

# ---------------- Crossplane ke liye IAM user ----------------
# Crossplane (VectorStore API) teams ke liye S3 buckets banata hai.
# Permission sirf "aiforge-vs-*" naam wale buckets tak (least privilege).
# Access key Terraform se NAHI banate (warna secret state file mein jaata):
# Console se key bana ke seedha Vault mein daalna hai (guide F3).
resource "aws_iam_user" "crossplane" {
  name = "${local.name}-crossplane"
}

data "aws_iam_policy_document" "crossplane_s3" {
  statement {
    sid = "ManageVectorStoreBuckets"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucket*",
      "s3:PutBucket*",
      "s3:DeleteBucketPolicy",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetAccelerateConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetAnalyticsConfiguration",
      "s3:GetIntelligentTieringConfiguration",
      "s3:GetInventoryConfiguration",
      "s3:GetMetricsConfiguration",
      "s3:GetObjectLockConfiguration",
    ]
    resources = ["arn:aws:s3:::aiforge-vs-*"]
  }
  statement {
    sid       = "ListAll"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "crossplane" {
  name   = "vectorstore-s3"
  user   = aws_iam_user.crossplane.name
  policy = data.aws_iam_policy_document.crossplane_s3.json
}
