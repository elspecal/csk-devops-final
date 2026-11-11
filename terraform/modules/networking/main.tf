locals {
  named_subnets   = { for sn in var.subnets : sn.name => sn }
  public_subnets  = { for sn in var.subnets : sn.name => sn if sn.type == "public" }
  private_subnets = { for sn in var.subnets : sn.name => sn if sn.type == "private" }
  all_sn_ids      = merge({ for k, sn in aws_subnet.public : k => sn.id }, { for k, sn in aws_subnet.private : k => sn.id })
  nat_subnet_name = element([for sn in var.subnets : sn.name if sn.type == "public"], 0)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-igw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[local.nat_subnet_name].id

  tags = {
    Name = "${var.project}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_subnet" "public" {
  # kubernetes.io/role/elb=1 -> internet-facing load balancers are placed here
  for_each = local.public_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = "${var.region}${each.value.az}"

  tags = {
    Name                                        = "${var.project}-${each.key}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  # kubernetes.io/role/internal-elb=1 -> internal load balancers are placed here
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = "${var.region}${each.value.az}"

  tags = {
    Name                                        = "${var.project}-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project}-rt-public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project}-rt-private"
  }
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}
