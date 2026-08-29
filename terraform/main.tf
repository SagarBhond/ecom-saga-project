terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
<<<<<<< HEAD
=======

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
>>>>>>> 4e7f136 (Update E-Commerce Saga project)
  }
}

# ============================================================
# AWS PROVIDER
# ============================================================

provider "aws" {
  region = var.aws_region
}

# ============================================================
# HTTP PROVIDER
# Used to automatically detect the public IP of the machine
# running Terraform.
# ============================================================

provider "http" {}

data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = "${trimspace(data.http.my_public_ip.response_body)}/32"
}

# ============================================================
# DEFAULT VPC
# ============================================================

data "aws_vpc" "default" {
  default = true
}

# ============================================================
# DEFAULT VPC SUBNETS
# ============================================================

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================================
# AMAZON LINUX 2023 AMI
# ============================================================

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================
# SECURITY GROUP
# ============================================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"
  vpc_id      = data.aws_vpc.default.id

  # ----------------------------------------------------------
  # SSH
  # Automatically restricted to Terraform runner public IP
  # ----------------------------------------------------------

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []

    content {
      description = "SSH from Terraform runner public IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [local.my_ip_cidr]
    }
  }

  # ----------------------------------------------------------
  # ORDER SERVICE
  # ----------------------------------------------------------

  ingress {
    description = "Order Service"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # INVENTORY SERVICE
  # ----------------------------------------------------------

  ingress {
    description = "Inventory Service"
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # PAYMENT SERVICE
  # ----------------------------------------------------------

  ingress {
    description = "Payment Service"
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # NOTIFICATION SERVICE
  # ----------------------------------------------------------

  ingress {
    description = "Notification Service"
    from_port   = 8084
    to_port     = 8084
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # KAFKA UI
  # Only accessible from automatically detected public IP
  # ----------------------------------------------------------

  dynamic "ingress" {
    for_each = var.expose_kafka_ui ? [1] : []

    content {
      description = "Kafka UI from Terraform runner public IP"
      from_port   = 8090
      to_port     = 8090
      protocol    = "tcp"
      cidr_blocks = [local.my_ip_cidr]
    }
  }

  # ----------------------------------------------------------
  # GRAFANA
  # ----------------------------------------------------------

  dynamic "ingress" {
    for_each = var.expose_grafana ? [1] : []

    content {
      description = "Grafana from Terraform runner public IP"
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = [local.my_ip_cidr]
    }
  }

  # ----------------------------------------------------------
  # PROMETHEUS
  # ----------------------------------------------------------

  dynamic "ingress" {
    for_each = var.expose_prometheus ? [1] : []

    content {
      description = "Prometheus from Terraform runner public IP"
      from_port   = 9090
      to_port     = 9090
      protocol    = "tcp"
      cidr_blocks = [local.my_ip_cidr]
    }
  }

  # ----------------------------------------------------------
  # LOKI
  # ----------------------------------------------------------

  dynamic "ingress" {
    for_each = var.expose_loki ? [1] : []

    content {
      description = "Loki from Terraform runner public IP"
      from_port   = 3100
      to_port     = 3100
      protocol    = "tcp"
      cidr_blocks = [local.my_ip_cidr]
    }
  }

  # ----------------------------------------------------------
  # OUTBOUND
  # ----------------------------------------------------------

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# ============================================================
# IAM ROLE
# ============================================================

resource "aws_iam_role" "instance" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# CLOUDWATCH AGENT PERMISSION
# ============================================================

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ============================================================
# SSM SESSION MANAGER
# ============================================================

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ============================================================
# EC2 DESCRIBE PERMISSION
# ============================================================

resource "aws_iam_role_policy" "ec2_describe" {
  name = "${var.project_name}-ec2-describe"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]

        Resource = "*"
      }
    ]
  })
}

# ============================================================
# INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance.name
}

# ============================================================
# CLOUDWATCH LOG GROUP
# ============================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/app"
  retention_in_days = var.log_retention_days
}

# ============================================================
# APPLICATION EC2
# ============================================================

resource "aws_instance" "app" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  iam_instance_profile = aws_iam_instance_profile.instance.name

  associate_public_ip_address = true

  key_name = var.enable_ssh ? var.key_name : null

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = templatefile(
    "${path.module}/user_data.sh",
    {
      project_name = var.project_name
    }
  )

  tags = {
    Name    = "${var.project_name}-app"
    Project = var.project_name
    Role    = "application"
  }
}

# ============================================================
# MONITORING EC2
# ============================================================

resource "aws_instance" "monitoring" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.monitoring_instance_type

  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  iam_instance_profile = aws_iam_instance_profile.instance.name

  associate_public_ip_address = true

  key_name = var.enable_ssh ? var.key_name : null

  root_block_device {
    volume_size = var.monitoring_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = templatefile(
    "${path.module}/monitoring_user_data.sh",
    {
      project_name = var.project_name
    }
  )

  tags = {
    Name    = "${var.project_name}-monitoring"
    Project = var.project_name
    Role    = "monitoring"
  }
}

# ============================================================
# APPLICATION STATUS CHECK RECOVERY
# ============================================================

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name = "${var.project_name}-status-check-failed"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2

  metric_name = "StatusCheckFailed_System"
  namespace   = "AWS/EC2"

  period    = 60
  statistic = "Maximum"
  threshold = 0

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_description = "Recover application EC2 after system status check failure."

  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:recover"
  ]
}

# ============================================================
# CPU ALARM
# ============================================================

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name = "${var.project_name}-cpu-high"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5

  metric_name = "CPUUtilization"
  namespace   = "AWS/EC2"

  period    = 60
  statistic = "Average"
  threshold = 80

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_description = "CPU above 80% for 5 consecutive minutes."
}

# ============================================================
# CLOUDWATCH DASHBOARD
# ============================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [

      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              aws_instance.app.id
            ]
          ]

          view    = "timeSeries"
          stacked = false
          region  = var.aws_region

          title = "Application CPU Utilization"
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              aws_instance.monitoring.id
            ]
          ]

          view    = "timeSeries"
          stacked = false
          region  = var.aws_region

          title = "Monitoring CPU Utilization"
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/EC2",
              "NetworkIn",
              "InstanceId",
              aws_instance.app.id
            ],
            [
              "AWS/EC2",
              "NetworkOut",
              "InstanceId",
              aws_instance.app.id
            ]
          ]

          view    = "timeSeries"
          stacked = false
          region  = var.aws_region

          title = "Application Network Traffic"
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/EC2",
              "NetworkIn",
              "InstanceId",
              aws_instance.monitoring.id
            ],
            [
              "AWS/EC2",
              "NetworkOut",
              "InstanceId",
              aws_instance.monitoring.id
            ]
          ]

          view    = "timeSeries"
          stacked = false
          region  = var.aws_region

          title = "Monitoring Network Traffic"
        }
      }
    ]
  })
}