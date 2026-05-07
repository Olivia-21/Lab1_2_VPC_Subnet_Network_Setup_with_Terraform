# =============================================================================
# Networking Module — Input Variables
# =============================================================================

variable "environment" {
  description = "Deployment environment (dev, prod). Used in resource naming."
  type        = string
}

variable "region" {
  description = "AWS region where all networking resources will be created."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = <<-EOT
    CIDR block for the VPC.
    10.0.0.0/16 = 65,536 possible IP addresses.
    RFC 1918 private range — not internet routable.
  EOT
  type        = string
  default     = "10.0.0.0/16"
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
variable "public_subnet_cidr" {
  description = "CIDR for the public subnet. Houses the NAT Gateway."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_1a_cidr" {
  description = "CIDR for private subnet 1a (us-east-1a). Houses databases."
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_1b_cidr" {
  description = "CIDR for private subnet 1b (us-east-1b). Houses compute (EC2, Lambda, Glue)."
  type        = string
  default     = "10.0.3.0/24"
}

# -----------------------------------------------------------------------------
# NAT Gateway — off by default to save costs ($0.32/hour = ~$232/month)
# Set to true only when private subnets need outbound internet access
# -----------------------------------------------------------------------------
variable "enable_nat_gateway" {
  description = <<-EOT
    Whether to create a NAT Gateway and Elastic IP.
    WARNING: NAT Gateway costs ~$232/month if left running 24/7.
    Set to true only when needed. Delete when done (see lab teardown steps).
  EOT
  type        = bool
  default     = false
}
