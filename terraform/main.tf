provider "aws" {
    region = var.aws_region

    default_tags {
      tags = {
        lab = "CDEM2"
        ManagedBy = "Terraform"
      }
    }
}


# =============================================================================
# Lab 1.2 — Networking
# =============================================================================

module "networking" {
  source      = "../modules/networking"
  environment = "dev"
  region      = "us-east-1"

  # NAT Gateway off by default — costs $0.32/hour (~$232/month)
  # Set to true only when private subnets need outbound internet access
  enable_nat_gateway = false
}



