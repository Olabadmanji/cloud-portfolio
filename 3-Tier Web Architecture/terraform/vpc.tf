# VPC & IGW
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "prod-3tier-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "prod-igw" }
}

# Public Subnets
resource "aws_subnet" "public_2a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/20"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "public-web-2a" }
}

resource "aws_subnet" "public_2b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.16.0/20"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "public-web-2b" }
}

# Private App Subnets
resource "aws_subnet" "app_2a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.128.0/20"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "prod-private-app-2a" }
}

resource "aws_subnet" "app_2b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.144.0/20"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "prod-private-app-2b" }
}

# Private DB Subnets
resource "aws_subnet" "db_2a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "prod-private-db-2a" }
}

resource "aws_subnet" "db_2b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "prod-private-db-2b" }
}

# NAT Gateways & Elastic IPs
resource "aws_eip" "nat_a" { domain = "vpc" }
resource "aws_eip" "nat_b" { domain = "vpc" }

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_2a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "prod-nat-2a" }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_2b.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "prod-nat-2b" }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "prod-rtb-public" }
}

resource "aws_route_table" "app_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  tags = { Name = "prod-rtb-app-2a" }
}

resource "aws_route_table" "app_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "prod-rtb-app-2b" }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "prod-rtb-db" }
}

# Route Table Associations
resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_2a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_2b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_2a.id
  route_table_id = aws_route_table.app_a.id
}
resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_2b.id
  route_table_id = aws_route_table.app_b.id
}
resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_2a.id
  route_table_id = aws_route_table.db.id
}
resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_2b.id
  route_table_id = aws_route_table.db.id
}