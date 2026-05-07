# =============================================================================
# Networking Module
# =============================================================================
# Creates the complete network infrastructure for the data platform:
#
#   1. VPC
#   2. Subnets (1 public, 2 private in different AZs)
#   3. Internet Gateway
#   4. Elastic IP + NAT Gateway (optional — controlled by var.enable_nat_gateway)
#   5. Route Tables (public + private)
#   6. Security Groups (public NAT, private compute, private database)
#   7. VPC Endpoints (S3 Gateway, DynamoDB Gateway, Secrets Manager Interface)
#
# Traffic flow:
#   Internet → IGW → Public Subnet → NAT → Private Subnets
#   Private Subnets → S3/DynamoDB via VPC Endpoints (no internet needed)
# =============================================================================

locals {
  name_prefix = "data-platform-${var.environment}"
}

# =============================================================================
# 1. VPC
# =============================================================================
# The container for all networking resources.
# 10.0.0.0/16 gives us 65,536 IP addresses to work with.
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true    # allows EC2 instances to get DNS names
  enable_dns_support   = true    # required for VPC endpoints to work

  tags = {
    Name        = "${local.name_prefix}-vpc"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# 2. SUBNETS
# =============================================================================
# Public subnet  — houses NAT Gateway, accessible from internet
# Private 1a     — houses databases (us-east-1a)
# Private 1b     — houses compute: EC2, Lambda, Glue (us-east-1b)
#
# Two private subnets in DIFFERENT AZs = redundancy.
# If us-east-1a fails, us-east-1b keeps running.
# =============================================================================

resource "aws_subnet" "public_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = "${var.region}a"

  # Instances launched here get a public IP automatically
  map_public_ip_on_launch = true

  tags = {
    Name        = "public-subnet-1a"
    Type        = "public"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_1a_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name        = "private-subnet-1a"
    Type        = "private"
    Purpose     = "databases"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_1b_cidr
  availability_zone = "${var.region}b"

  tags = {
    Name        = "private-subnet-1b"
    Type        = "private"
    Purpose     = "compute"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# 3. INTERNET GATEWAY
# =============================================================================
# The border checkpoint between your VPC and the internet.
# Not a firewall — security groups handle that.
# Must be attached to VPC before any internet traffic can flow.
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${local.name_prefix}-igw"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# 4. ELASTIC IP + NAT GATEWAY (optional)
# =============================================================================
# NAT Gateway: allows private servers to REACH internet (for updates/downloads)
# but prevents internet from REACHING private servers.
#
# count = 1 if enabled, 0 if disabled.
# This is how Terraform conditionally creates resources.
#
# WARNING: costs ~$232/month if left running 24/7.
# Set var.enable_nat_gateway = false when not needed.
# =============================================================================

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0    # only create if NAT is enabled
  domain = "vpc"

  tags = {
    Name        = "${local.name_prefix}-nat-eip"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0    # only create if enabled
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_1a.id            # MUST be in public subnet

  tags = {
    Name        = "${local.name_prefix}-nat"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# 5. ROUTE TABLES
# =============================================================================
# Route tables = GPS for traffic. Tell packets where to go.
#
# Public RT:  unknown traffic → Internet Gateway
# Private RT: unknown traffic → NAT Gateway (if enabled) or blocked
# =============================================================================

# -----------------------------------------------------------------------------
# Public Route Table
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Send all unknown traffic to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "public-route-table"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Associate public route table with public subnet
resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Private Route Table
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "private-route-table"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Only add the NAT route if NAT Gateway is enabled
resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

# Associate private route table with BOTH private subnets
resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# 6. SECURITY GROUPS
# =============================================================================
# Security groups = firewalls for individual resources.
# Deny by default — only explicitly allowed traffic gets through.
#
# sg-public-nat      → HTTPS inbound from anywhere
# sg-private-compute → all traffic from itself + public SG
# sg-private-db      → MySQL (3306) + PostgreSQL (5432) from compute SG only
# =============================================================================

# -----------------------------------------------------------------------------
# Public Security Group (NAT area)
# -----------------------------------------------------------------------------
resource "aws_security_group" "public_nat" {
  name        = "public-nat-sg"
  description = "Security group for public subnet. Allows HTTPS inbound only."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (default for security groups)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "public-nat-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Private Compute Security Group (EC2, Lambda, Glue)
# -----------------------------------------------------------------------------
resource "aws_security_group" "private_compute" {
  name        = "private-compute-sg"
  description = "Security group for compute in private subnets. Allows internal traffic."
  vpc_id      = aws_vpc.main.id

  # Allow all traffic from itself (servers in compute subnet talk to each other)
  ingress {
    description = "All traffic from within this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all traffic from public security group (NAT Gateway → compute servers)
  ingress {
    description     = "All traffic from public security group"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.public_nat.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "private-compute-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Private Database Security Group (RDS)
# -----------------------------------------------------------------------------
resource "aws_security_group" "private_db" {
  name        = "private-db-sg"
  description = "Security group for RDS databases. Only allows from compute layer."
  vpc_id      = aws_vpc.main.id

  # MySQL — only from compute security group
  ingress {
    description     = "MySQL from compute subnet"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.private_compute.id]
  }

  # PostgreSQL — only from compute security group
  ingress {
    description     = "PostgreSQL from compute subnet"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.private_compute.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "private-db-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# 7. VPC ENDPOINTS
# =============================================================================
# Secret passages — private servers reach AWS services WITHOUT internet.
#
# Without endpoints: Private → NAT → Internet → S3   ($0.32/hr + $0.02/GB)
# With endpoints:    Private → Endpoint → S3          (FREE or $7/month)
#
# Gateway endpoints (FREE):  S3, DynamoDB
# Interface endpoints (~$7/month): Secrets Manager
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Gateway Endpoint — FREE
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  # Only associate with private route table
  # Private servers use this endpoint, not public
  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name        = "${local.name_prefix}-s3-endpoint"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# DynamoDB Gateway Endpoint — FREE
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name        = "${local.name_prefix}-dynamodb-endpoint"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Secrets Manager Interface Endpoint — ~$7/month
# Deployed in BOTH private subnets for redundancy across AZs
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true    # allows using standard secretsmanager DNS names

  subnet_ids = [
    aws_subnet.private_1a.id,
    aws_subnet.private_1b.id    # both AZs for redundancy
  ]

  security_group_ids = [aws_security_group.private_compute.id]

  tags = {
    Name        = "${local.name_prefix}-secretsmanager-endpoint"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
