terraform {
  cloud {
    organization = "slourp-org"
    workspaces {
      name = "learn-terraform-gh-actions"
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

############################################################
################### DECLARING MY CLUSTER ###################
############################################################

resource "aws_ecs_cluster" "app_cluster" {
  name = var.cluster_name
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

##########################################################################################
################### GETTING MY DEFAULT VPC, SECURITY GROUP AND SUBNETS ###################
##########################################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "default" {
  name = "default"
}

data "aws_subnets" "default" {}

##################################################################
################### DECLARING MY LOAD BALANCER ###################
##################################################################

resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.default.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "app_target_group" {
  name        = "app-target-group"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path = "/health"
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
    subnets          = data.aws_subnets.default.ids
    security_groups  = [data.aws_security_group.default.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_target_group.arn
    container_name   = "fargate-ci-guide-app"
    container_port   = 3000
  }
}

##################################################################
################### DECLARING MY VPC ENDPOINTS ###################
##################################################################

data "aws_route_table" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.eu-west-3.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.default.id]
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-3.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [data.aws_security_group.default.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-3.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [data.aws_security_group.default.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-3.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [data.aws_security_group.default.id]
  private_dns_enabled = true
}
