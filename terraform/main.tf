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

resource "aws_ecs_cluster" "app_cluster" {
  name = var.cluster_name
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name = aws_ecs_cluster.app_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

data "aws_ecs_task_definition" "service" {
  task_definition = "fargate-ci-guide"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {}

resource "aws_ecs_service" "service" {
  name          = "app-service"
  cluster       = aws_ecs_cluster.app_cluster.id
  desired_count = 2

  task_definition = data.aws_ecs_task_definition.service.arn

  launch_type = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
  }
}
