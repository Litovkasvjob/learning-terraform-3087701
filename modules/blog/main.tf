# Fetch latest AMI for Bitnami Tomcat
data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner]
}

# VPC Module
module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}

# Security Group
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name    = "${var.environment.name}-blog"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

# Auto Scaling Group
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.1.0"

  name              = "${var.environment.name}-blog-asg"
  min_size          = var.asg_min_size
  max_size          = var.asg_max_size
  desired_capacity  = 1

  vpc_zone_identifier = module.blog_vpc.public_subnets
  # target_group_arns   = module.blog_alb.target_group_arns
  security_groups     = [module.blog_sg.security_group_id]
  instance_type       = var.instance_type
  image_id            = data.aws_ami.app_ami.id
}

# Application Load Balancer (ALB)
module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"
  version = "9.13.0"

  name                = "${var.environment.name}-blog-alb"
  load_balancer_type  = "application"

  vpc_id              = module.blog_vpc.vpc_id
  subnets             = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  listeners = [
    {
      port     = 80
      protocol = "HTTP"
      forward  = {
        target_group_key = "ex-instance"
      }
    }
  ]

  target_groups = {
    ex-instance = {
      name_prefix = "${var.environment.name}-"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      create_attachment = false 
    }
  }

  tags = {
    Environment = var.environment.name
  }
}

resource "aws_autoscaling_attachment" "asg_alb_attachment" {
  autoscaling_group_name = module.autoscaling.autoscaling_group_id
  lb_target_group_arn    = module.blog_alb.target_groups["ex-instance"].arn
}
