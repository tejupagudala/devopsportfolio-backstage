
# ==========================================
# Backstage IDP - VPC and Networking
# Region: us-east-1
# ==========================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "backstage-idp"

  azs = slice(
    data.aws_availability_zones.available.names,
    0,
    2
  )
}

# VPC
resource "aws_vpc" "idp" {
  cidr_block           = "10.60.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "idp" {
  vpc_id = aws_vpc.idp.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# Public subnets (ALB and NAT)
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.idp.id
  cidr_block              = "10.60.${count.index + 1}.0/24"
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${local.name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private subnets (EKS worker nodes)
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.idp.id
  cidr_block        = "10.60.${count.index + 11}.0/24"
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "${local.name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.idp.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.idp.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }
}

# Single NAT Gateway to minimize cost
resource "aws_nat_gateway" "idp" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [
    aws_internet_gateway.idp
  ]

  tags = {
    Name = "${local.name}-nat"
  }
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.idp.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.idp.id
  }

  tags = {
    Name = "${local.name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Outputs for future EKS configuration
output "vpc_id" {
  value = aws_vpc.idp.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
