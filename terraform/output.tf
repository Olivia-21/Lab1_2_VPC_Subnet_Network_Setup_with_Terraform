#Print the ARN after apply(for documentation file)
output "data_engineer_role_arn" {
  value = module.data_engineer_role.role_arn
}

# =============================================================================
# Outputs — Lab 1.2
# =============================================================================

output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_id" {
  value = module.networking.public_subnet_id
}

output "private_subnet_1a_id" {
  value = module.networking.private_subnet_1a_id
}

output "private_subnet_1b_id" {
  value = module.networking.private_subnet_1b_id
}

output "sg_private_compute_id" {
  value = module.networking.sg_private_compute_id
}

output "sg_private_db_id" {
  value = module.networking.sg_private_db_id
}