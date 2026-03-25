terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Uncomment to use S3 backend for state management
  # backend "s3" {
  #   bucket         = "nextcloud-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Nextcloud"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ============================================================================
# VPC AND NETWORKING
# ============================================================================

resource "aws_vpc" "nextcloud" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "nextcloud-vpc-${var.environment}"
  }
}

resource "aws_subnet" "nextcloud_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.nextcloud.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "nextcloud-public-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "nextcloud" {
  vpc_id = aws_vpc.nextcloud.id

  tags = {
    Name = "nextcloud-igw-${var.environment}"
  }
}

resource "aws_route_table" "nextcloud_public" {
  vpc_id = aws_vpc.nextcloud.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nextcloud.id
  }

  tags = {
    Name = "nextcloud-public-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "nextcloud_public" {
  count          = length(aws_subnet.nextcloud_public)
  subnet_id      = aws_subnet.nextcloud_public[count.index].id
  route_table_id = aws_route_table.nextcloud_public.id
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

resource "aws_security_group" "nextcloud_alb" {
  name        = "nextcloud-alb-${var.environment}"
  description = "Security group for Nextcloud ALB"
  vpc_id      = aws_vpc.nextcloud.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nextcloud-alb-sg-${var.environment}"
  }
}

resource "aws_security_group" "nextcloud_app" {
  name        = "nextcloud-app-${var.environment}"
  description = "Security group for Nextcloud application"
  vpc_id      = aws_vpc.nextcloud.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nextcloud_alb.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nextcloud_alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nextcloud-app-sg-${var.environment}"
  }
}

resource "aws_security_group" "nextcloud_db" {
  name        = "nextcloud-db-${var.environment}"
  description = "Security group for Nextcloud database"
  vpc_id      = aws_vpc.nextcloud.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.nextcloud_app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nextcloud-db-sg-${var.environment}"
  }
}

# ============================================================================
# EC2 INSTANCES
# ============================================================================

resource "aws_instance" "nextcloud" {
  count                       = var.instance_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.nextcloud_public[count.index % length(aws_subnet.nextcloud_public)].id
  vpc_security_group_ids      = [aws_security_group.nextcloud_app.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.nextcloud.name

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    repository_url = var.repository_url
    branch         = var.branch
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "nextcloud-app-${count.index + 1}-${var.environment}"
  }
}

# ============================================================================
# RDS DATABASE
# ============================================================================

resource "aws_db_subnet_group" "nextcloud" {
  name       = "nextcloud-${var.environment}"
  subnet_ids = [aws_subnet.nextcloud_public[0].id, aws_subnet.nextcloud_public.length > 1 ? aws_subnet.nextcloud_public[1].id : aws_subnet.nextcloud_public[0].id]

  tags = {
    Name = "nextcloud-db-subnet-${var.environment}"
  }
}

resource "aws_rds_cluster" "nextcloud" {
  cluster_identifier      = "nextcloud-${var.environment}"
  engine                  = "aurora-postgresql"
  engine_version          = var.postgres_version
  database_name           = "nextcloud"
  master_username         = "postgres"
  master_password         = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.nextcloud.name
  vpc_security_group_ids  = [aws_security_group.nextcloud_db.id]
  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = var.environment != "production"
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds.arn

  tags = {
    Name = "nextcloud-db-${var.environment}"
  }
}

resource "aws_rds_cluster_instance" "nextcloud" {
  count              = var.db_instance_count
  cluster_identifier = aws_rds_cluster.nextcloud.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.nextcloud.engine
  engine_version     = aws_rds_cluster.nextcloud.engine_version
  publicly_accessible = false

  tags = {
    Name = "nextcloud-db-instance-${count.index + 1}-${var.environment}"
  }
}

# ============================================================================
# LOAD BALANCER
# ============================================================================

resource "aws_lb" "nextcloud" {
  name               = "nextcloud-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nextcloud_alb.id]
  subnets            = aws_subnet.nextcloud_public[*].id

  enable_deletion_protection = var.environment == "production"

  tags = {
    Name = "nextcloud-alb-${var.environment}"
  }
}

resource "aws_lb_target_group" "nextcloud" {
  name        = "nextcloud-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.nextcloud.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/status.php"
    matcher             = "200"
  }

  tags = {
    Name = "nextcloud-tg-${var.environment}"
  }
}

resource "aws_lb_target_group_attachment" "nextcloud" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.nextcloud.arn
  target_id        = aws_instance.nextcloud[count.index].id
  port             = 80
}

resource "aws_lb_listener" "nextcloud_http" {
  load_balancer_arn = aws_lb.nextcloud.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "nextcloud_https" {
  load_balancer_arn = aws_lb.nextcloud.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.nextcloud.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nextcloud.arn
  }
}

# ============================================================================
# SECRETS AND CREDENTIALS
# ============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "nextcloud_db" {
  name                    = "nextcloud/postgres-password-${var.environment}"
  recovery_window_in_days = 7

  tags = {
    Name = "nextcloud-db-secret-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "nextcloud_db" {
  secret_id = aws_secretsmanager_secret.nextcloud_db.id
  secret_string = jsonencode({
    username = "postgres"
    password = random_password.db_password.result
    engine   = "postgresql"
    host     = aws_rds_cluster.nextcloud.endpoint
    port     = 5432
    dbname   = "nextcloud"
  })
}

# ============================================================================
# ENCRYPTION
# ============================================================================

resource "aws_kms_key" "rds" {
  description             = "KMS key for Nextcloud RDS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "nextcloud-rds-key-${var.environment}"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/nextcloud-rds-${var.environment}"
  target_key_id = aws_kms_key.rds.key_id
}

# ============================================================================
# IAM ROLES
# ============================================================================

resource "aws_iam_role" "nextcloud_instance" {
  name = "nextcloud-instance-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "nextcloud_instance" {
  name = "nextcloud-instance-policy-${var.environment}"
  role = aws_iam_role.nextcloud_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.nextcloud_db.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.rds.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nextcloud" {
  name = "nextcloud-instance-profile-${var.environment}"
  role = aws_iam_role.nextcloud_instance.name
}

# ============================================================================
# SSL CERTIFICATE
# ============================================================================

resource "aws_acm_certificate" "nextcloud" {
  domain_name            = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method      = "DNS"
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "nextcloud-cert-${var.environment}"
  }
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
