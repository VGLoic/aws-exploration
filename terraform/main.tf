#################################################
################### PROVIDERS ###################
#################################################

terraform {
  cloud {
    organization = "slourp-org"
    workspaces {
      name = "ecs-fargate-guide"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-3"
}

###########################################
################### VPC ###################
###########################################

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "AWS Fargate Guide VPC"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "AWS Fargate Guide VPC IG"
  }
}

resource "aws_route_table" "rt_for_internet" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Route Table for internet access"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.rt_for_internet.id
}

######################################################
################### SECURITY GROUP ###################
######################################################

resource "aws_security_group" "allow_traffic" {
  name        = "AwsFargateGuide Allow Traffic VPC"
  description = "Allow all outbound traffic, allow inbound traffic within a VPC, allow inbound traffic on port 80"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "AwsFargate Allow Traffic VPC"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ipv4_port_80" {
  security_group_id = aws_security_group.allow_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ipv6_port_80" {
  security_group_id = aws_security_group.allow_traffic.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_all_traffic_within_security_group" {
  security_group_id            = aws_security_group.allow_traffic.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.allow_traffic.id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_traffic.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

############################################################
################### DECLARING MY CLUSTER ###################
############################################################

resource "aws_ecs_cluster" "app_cluster" {
  name = var.cluster_name

  tags = {
    Name = "Fargate Guide Cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name = aws_ecs_cluster.app_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

##################################################################
################### GETTING MY TASK DEFINITION ###################
##################################################################

data "aws_ecs_task_definition" "service" {
  task_definition = "fargate-ci-guide"
}

##################################################################
################### DECLARING MY LOAD BALANCER ###################
##################################################################

resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_traffic.id]
  subnets            = [for subnet in aws_subnet.public_subnets : subnet.id]

  tags = {
    Name = "Fargate Guide LB"
  }
}

resource "aws_lb_target_group" "app_target_group" {
  name        = "app-target-group"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path = "/health"
  }

  tags = {
    Name = "Fargate Guide LB TG"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }

  tags = {
    Name = "Fargate Guide LB Listener"
  }
}

############################################################
################### DECLARING MY SERVICE ###################
############################################################

resource "aws_ecs_service" "service" {
  name          = "app-service"
  cluster       = aws_ecs_cluster.app_cluster.id
  desired_count = 2

  task_definition = data.aws_ecs_task_definition.service.arn

  launch_type = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.private_subnets : subnet.id]
    security_groups  = [aws_security_group.allow_traffic.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_target_group.arn
    container_name   = "fargate-ci-guide-app"
    container_port   = 3000
  }

  tags = {
    Name = "Fargate Guide Service"
  }
}

##################################################################
################### DECLARING MY VPC ENDPOINTS ###################
##################################################################

data "aws_route_table" "rt_private" {
  vpc_id = aws_vpc.main.id
  filter {
    name   = "association.main"
    values = [true]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.rt_private.id]

  tags = {
    Name = "S3 Gateway"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-3.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private_subnets : subnet.id]
  security_group_ids  = [aws_security_group.allow_traffic.id]
  private_dns_enabled = true

  tags = {
    Name = "ECR API"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-3.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private_subnets : subnet.id]
  security_group_ids  = [aws_security_group.allow_traffic.id]
  private_dns_enabled = true

  tags = {
    Name = "ECR API"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-3.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private_subnets : subnet.id]
  security_group_ids  = [aws_security_group.allow_traffic.id]
  private_dns_enabled = true

  tags = {
    Name = "logs"
  }
}
