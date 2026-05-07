# =============================================================================
# Networking Module — Outputs
# =============================================================================
# These values are consumed by other modules and by envs/dev/main.tf.
# Future labs will use subnet IDs (for RDS, EC2, Glue)
# and security group IDs (for database and compute resources).
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC — referenced by all resources that live inside it"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
output "public_subnet_id" {
  description = "ID of the public subnet — used for NAT Gateway and load balancers"
  value       = aws_subnet.public_1a.id
}

output "private_subnet_1a_id" {
  description = "ID of private subnet 1a (us-east-1a) — used for databases"
  value       = aws_subnet.private_1a.id
}

output "private_subnet_1b_id" {
  description = "ID of private subnet 1b (us-east-1b) — used for compute (EC2, Lambda, Glue)"
  value       = aws_subnet.private_1b.id
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
output "sg_public_nat_id" {
  description = "ID of the public NAT security group"
  value       = aws_security_group.public_nat.id
}

output "sg_private_compute_id" {
  description = "ID of the private compute security group — used by EC2, Lambda, Glue"
  value       = aws_security_group.private_compute.id
}

output "sg_private_db_id" {
  description = "ID of the private database security group — used by RDS"
  value       = aws_security_group.private_db.id
}

# -----------------------------------------------------------------------------
# NAT Gateway (only populated when var.enable_nat_gateway = true)
# -----------------------------------------------------------------------------
output "nat_gateway_id" {
  description = "ID of the NAT Gateway — empty if enable_nat_gateway is false"
  value       = var.enable_nat_gateway ? aws_nat_gateway.main[0].id : null
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway — empty if enable_nat_gateway is false"
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}

# -----------------------------------------------------------------------------
# VPC Endpoints
# -----------------------------------------------------------------------------
output "s3_endpoint_id" {
  description = "ID of the S3 VPC Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "dynamodb_endpoint_id" {
  description = "ID of the DynamoDB VPC Gateway Endpoint"
  value       = aws_vpc_endpoint.dynamodb.id
}

output "secretsmanager_endpoint_id" {
  description = "ID of the Secrets Manager VPC Interface Endpoint"
  value       = aws_vpc_endpoint.secretsmanager.id
}
