data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "aws-ha-three-tier"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  subnets = {
    "public-a" = { tier = "public", az = 0, cidr = "10.10.0.0/24" }
    "public-b" = { tier = "public", az = 1, cidr = "10.10.1.0/24" }
    "app-a"    = { tier = "app", az = 0, cidr = "10.10.10.0/24" }
    "app-b"    = { tier = "app", az = 1, cidr = "10.10.11.0/24" }
    "db-a"     = { tier = "db", az = 0, cidr = "10.10.20.0/24" }
    "db-b"     = { tier = "db", az = 1, cidr = "10.10.21.0/24" }
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"

  tags = { Name = local.name }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = local.azs[each.value.az]

  tags = { Name = "${local.name}-${each.key}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${local.name}-nat" }
}

resource "aws_nat_gateway" "main" {
  availability_mode = "zonal"
  allocation_id     = aws_eip.nat.id
  subnet_id         = aws_subnet.this["public-a"].id

  tags = { Name = "${local.name}-nat" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${local.name}-app" }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  route  = []

  tags = { Name = "${local.name}-db" }
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id = aws_subnet.this[each.key].id
  route_table_id = {
    public = aws_route_table.public.id
    app    = aws_route_table.app.id
    db     = aws_route_table.db.id
  }[each.value.tier]
}
