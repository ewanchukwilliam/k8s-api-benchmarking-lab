# Production Environment

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use S3 backend (recommended for teams)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      ManagedBy   = "terraform"
      Project     = "devops-lab"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "devops-lab-prod"
}

variable "domain" {
  description = "Root domain name"
  type        = string
  default     = "codeseeker.dev"
}

variable "subdomain" {
  description = "Subdomain for the application"
  type        = string
  default     = "api"
}

variable "create_hosted_zone" {
  description = "Create new hosted zone (false = use existing)"
  type        = bool
  default     = false
}

locals {
  azs = ["${var.aws_region}a", "${var.aws_region}b"]

  tags = {
    Environment = "prod"
    Cluster     = var.cluster_name
  }
}

# VPC
module "vpc" {
  source = "../../modules/vpc"

  name = var.cluster_name
  cidr = "10.0.0.0/16"
  azs  = local.azs
  tags = local.tags
}

# EKS Cluster
module "eks" {
  source = "../../modules/eks"

  name               = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  kubernetes_version = "1.29"

  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 5

  tags = local.tags
}

# DNS & SSL Certificate
module "dns" {
  source = "../../modules/dns"

  domain             = var.domain
  subdomain          = var.subdomain
  create_hosted_zone = var.create_hosted_zone
  tags               = local.tags
}

# ECR Repository
module "ecr" {
  source = "../../modules/ecr"

  repository_name = "health-service"
  tags            = local.tags
}

# Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# DNS Outputs
output "domain" {
  description = "Application domain"
  value       = module.dns.domain
}

output "certificate_arn" {
  description = "ACM certificate ARN (use in ingress)"
  value       = module.dns.certificate_arn
}

output "name_servers" {
  description = "Update these at your domain registrar"
  value       = module.dns.zone_name_servers
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.dns.zone_id
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR repository URL for docker push"
  value       = module.ecr.repository_url
}

output "docker_login_command" {
  description = "Command to login to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.repository_url}"
}

output "docker_push_commands" {
  description = "Commands to build and push image to ECR"
  value       = <<-EOT
    docker build -t health-service:local .
    docker tag health-service:local ${module.ecr.repository_url}:latest
    docker push ${module.ecr.repository_url}:latest
  EOT
}
