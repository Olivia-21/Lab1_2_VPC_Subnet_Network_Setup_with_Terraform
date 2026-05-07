# Lab 1.2 — VPC, Subnets & Network Setup for Data Platform

## Overview
This module provisions a production-ready VPC network for the data platform.
It implements **layered security** — databases are unreachable from the internet,
compute resources can reach the internet but not be reached, and AWS services
are accessed privately without internet traffic.

---

## Architecture

```
Infrastructure/
└── modules/
    └── networking/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Network Diagram

```
Internet
    │
    ▼
Internet Gateway (data-platform-igw)
    │
    ▼
┌─────────────────────────────────────────────────┐
│  VPC: 10.0.0.0/16  (data-platform-vpc)          │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  Public Subnet (10.0.1.0/24) us-east-1a  │   │
│  │  sg-public-nat                           │   │
│  │  └── NAT Gateway (optional)              │   │
│  └──────────────────────────────────────────┘   │
│           │                                      │
│           ▼ (outbound only)                      │
│  ┌───────────────────┐  ┌───────────────────┐   │
│  │ Private Subnet 1a │  │ Private Subnet 1b │   │
│  │ 10.0.2.0/24       │  │ 10.0.3.0/24       │   │
│  │ us-east-1a        │  │ us-east-1b        │   │
│  │ sg-private-db     │  │ sg-private-compute│   │
│  │ └── Databases     │  │ └── EC2/Lambda    │   │
│  └───────────────────┘  │    /Glue          │   │
│                          └───────────────────┘   │
│                                                  │
│  VPC Endpoints (private access to AWS services)  │
│  ├── S3 Gateway       (FREE)                     │
│  ├── DynamoDB Gateway (FREE)                     │
│  └── Secrets Manager Interface (~$7/month)       │
└─────────────────────────────────────────────────┘
```

---

## Resources Created

### VPC
| Setting | Value | Reason |
|---------|-------|--------|
| CIDR | 10.0.0.0/16 | 65,536 IP addresses, RFC 1918 private range |
| DNS Hostnames | Enabled | EC2 instances get DNS names |
| DNS Support | Enabled | Required for VPC endpoints to resolve |

---

### Subnets

| Name | CIDR | AZ | Type | Purpose |
|------|------|----|------|---------|
| public-subnet-1a | 10.0.1.0/24 | us-east-1a | Public | NAT Gateway, load balancers |
| private-subnet-1a | 10.0.2.0/24 | us-east-1a | Private | Databases (RDS) |
| private-subnet-1b | 10.0.3.0/24 | us-east-1b | Private | Compute (EC2, Lambda, Glue) |

> **Why two private subnets in different AZs?**
> If us-east-1a data centre fails, us-east-1b keeps running.
> AWS best practice: always use 2+ availability zones for redundancy.

---

### Internet Gateway
**Purpose:** Border checkpoint between your VPC and the internet. Not a firewall — security groups handle that.

---

### NAT Gateway (Optional — disabled by default)
**Purpose:** Allows private servers to reach the internet (for updates/downloads) but prevents the internet from reaching private servers.

```
Private server → NAT Gateway → Internet Gateway → Internet  ✅ outbound works
Internet → NAT Gateway → Private server                      ❌ inbound blocked
```

> **⚠️ Cost Warning:** NAT Gateway costs **~$232/month** if left running 24/7.
> Controlled by `enable_nat_gateway` variable (default: `false`).
> Only enable when private subnets need outbound internet access.

```hcl
# Enable when needed
module "networking" {
  enable_nat_gateway = true
}

# Disable to save costs
module "networking" {
  enable_nat_gateway = false
}
```

---

### Route Tables

| Table | Route | Target | Purpose |
|-------|-------|--------|---------|
| public-route-table | 0.0.0.0/0 | Internet Gateway | All unknown traffic → internet |
| private-route-table | 0.0.0.0/0 | NAT Gateway (if enabled) | All unknown traffic → NAT |

---

### Security Groups

#### sg-public-nat
| Rule | Type | Port | Source | Reason |
|------|------|------|--------|--------|
| Inbound | HTTPS | 443 | 0.0.0.0/0 | Encrypted web traffic only |
| Outbound | All | All | 0.0.0.0/0 | Allow all outbound |

#### sg-private-compute
| Rule | Type | Port | Source | Reason |
|------|------|------|--------|--------|
| Inbound | All | All | Self | Servers in group talk to each other |
| Inbound | All | All | sg-public-nat | NAT Gateway can reach compute |
| Outbound | All | All | 0.0.0.0/0 | Allow all outbound |

#### sg-private-db
| Rule | Type | Port | Source | Reason |
|------|------|------|--------|--------|
| Inbound | MySQL | 3306 | sg-private-compute | Only app servers reach MySQL |
| Inbound | PostgreSQL | 5432 | sg-private-compute | Only app servers reach PostgreSQL |
| Outbound | All | All | 0.0.0.0/0 | Allow all outbound |

> **Key principle:** Databases are ONLY reachable from compute servers.
> Even if an attacker gets into the public subnet, they cannot reach the database.

---

### VPC Endpoints

| Endpoint | Type | Cost | Purpose |
|----------|------|------|---------|
| S3 Gateway | Gateway | FREE | Private servers access S3 without internet |
| DynamoDB Gateway | Gateway | FREE | Private servers access DynamoDB without internet |
| Secrets Manager | Interface | ~$7/month | Private servers retrieve credentials without internet |

**Why endpoints instead of NAT for AWS services?**
```
Without endpoints: Private subnet → NAT ($0.32/hr) → Internet → S3
With endpoints:    Private subnet → VPC Endpoint (free) → S3

Cost saving: $230+/month on NAT data transfer
Security:    Data never leaves AWS network
Speed:       Shorter path, lower latency
```

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | required | Deployment environment (dev, prod) |
| `region` | us-east-1 | AWS region |
| `vpc_cidr` | 10.0.0.0/16 | VPC IP range |
| `public_subnet_cidr` | 10.0.1.0/24 | Public subnet range |
| `private_subnet_1a_cidr` | 10.0.2.0/24 | Private subnet 1a range |
| `private_subnet_1b_cidr` | 10.0.3.0/24 | Private subnet 1b range |
| `enable_nat_gateway` | false | Toggle NAT Gateway (costs ~$232/month) |

---

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID — referenced by all resources inside it |
| `public_subnet_id` | Used for load balancers and NAT Gateway |
| `private_subnet_1a_id` | Used for RDS database instances |
| `private_subnet_1b_id` | Used for EC2, Lambda, Glue resources |
| `sg_public_nat_id` | Public security group ID |
| `sg_private_compute_id` | Compute security group ID |
| `sg_private_db_id` | Database security group ID |
| `nat_gateway_id` | NAT Gateway ID (null if disabled) |
| `s3_endpoint_id` | S3 VPC endpoint ID |
| `dynamodb_endpoint_id` | DynamoDB VPC endpoint ID |
| `secretsmanager_endpoint_id` | Secrets Manager endpoint ID |

---

## Usage

```hcl
module "networking" {
  source      = "../modules/networking"
  environment = "dev"
  region      = "us-east-1"

  enable_nat_gateway = false    # set true only when needed
}
```

---

## Security Decisions

### Why databases in private subnet with no internet access?
```
2019: Capital One breach — 100 million records leaked
Root cause: Database accessible from internet
Prevention: Put databases in private subnet
Result: Even a misconfigured firewall can't expose them
```

### Why two private subnets?
```
Separation of concerns:
  private-subnet-1a → databases (RDS)
  private-subnet-1b → compute (EC2, Lambda, Glue)

If compute is compromised:
  Attacker is in 1b, databases are in 1a
  sg-private-db only allows port 3306/5432 from sg-private-compute
  Attacker still cannot access database directly
```

---

## Prerequisites
- Completed Lab 1.1 (IAM roles)
- AWS account with admin or PowerUser access
- Terraform >= 1.0

## Deployment

```bash
cd Infrastructure/terraform
terraform init
terraform plan
terraform apply
```

## Cost Breakdown

| Resource | Cost |
|----------|------|
| VPC | Free |
| Subnets | Free |
| Internet Gateway | Free |
| Route Tables | Free |
| Security Groups | Free |
| S3 Gateway Endpoint | Free |
| DynamoDB Gateway Endpoint | Free |
| Secrets Manager Endpoint | ~$7/month |
| NAT Gateway (if enabled) | ~$232/month |
| Elastic IP (if enabled) | Free when attached |

> **Teardown note:** Delete NAT Gateway when not in use to avoid charges.
> VPC, subnets, security groups and endpoints cost nothing to keep.
