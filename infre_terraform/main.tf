terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# DEFAULT VPC / SUBNET
# ============================================================================
# Uses the existing default VPC.
# No new VPC or NAT Gateway is created.
# ============================================================================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================================================
# AMAZON LINUX 2023 AMI
# ============================================================================

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================================
# SECURITY GROUP
# ============================================================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Security group for the ${var.project_name} deployment"
  vpc_id      = data.aws_vpc.default.id

  # --------------------------------------------------------------------------
  # Spring Boot services
  # Order       = 8081
  # Inventory   = 8082
  # Payment     = 8083
  # Notification= 8084
  # --------------------------------------------------------------------------

  ingress {
    description = "Spring Boot services"
    from_port   = 8081
    to_port     = 8084
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Grafana / Prometheus / Loki
  # Grafana    = 3000
  # Prometheus = 9090
  # Loki       = 3100
  # --------------------------------------------------------------------------

  ingress {
    description = "Observability Stack"
    from_port   = 3000
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # Exporters
  # cAdvisor     = 8080
  # Node Exporter= 9100
  # --------------------------------------------------------------------------

  ingress {
    description = "Exporters"
    from_port   = 8080
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --------------------------------------------------------------------------
  # SSH
  # Restricted to your detected public IP
  # --------------------------------------------------------------------------

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []

    content {
      description = "SSH restricted to Terraform runner IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.my_ip_cidr]
    }
  }

  # --------------------------------------------------------------------------
  # Kafka UI
  # --------------------------------------------------------------------------

  dynamic "ingress" {
    for_each = var.expose_kafka_ui ? [1] : []

    content {
      description = "Kafka UI"
      from_port   = 8090
      to_port     = 8090
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # --------------------------------------------------------------------------
  # All outbound traffic
  # --------------------------------------------------------------------------

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ============================================================================
# EC2 IAM ROLE
# ============================================================================

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

# ============================================================================
# CLOUDWATCH AGENT POLICY
# ============================================================================

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ============================================================================
# SSM POLICY
# ============================================================================

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ============================================================================
# EC2 DESCRIBE POLICY
# ============================================================================

resource "aws_iam_role_policy" "ec2_describe" {
  name = "${var.project_name}-ec2-describe"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ec2:DescribeInstances"
        ]

        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# INSTANCE PROFILE
# ============================================================================

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance.name
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/app"
  retention_in_days = var.log_retention_days
}

# ============================================================================
# MAIN APPLICATION EC2 INSTANCE
# ============================================================================

resource "aws_instance" "app" {

  ami = data.aws_ami.al2023.id

  instance_type = var.instance_type

  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  iam_instance_profile = aws_iam_instance_profile.instance.name

  # IMPORTANT:
  #
  # AWS key pair name = "pro"
  #
  # Local private key file = "pro.pem"
  #
  # Do NOT put "pro.pem" here.
  #
  key_name = var.enable_ssh ? var.key_name : null

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile(
    "${path.module}/user_data.sh",
    {
      project_name = var.project_name
    }
  )

  tags = {
    Name = "${var.project_name}-app"
  }

  depends_on = [
    aws_cloudwatch_log_group.app
  ]

  # user_data only runs on first boot. Changing this file after the instance
  # already exists must NEVER trigger a destroy/recreate of a live instance -
  # apply any future bootstrap changes manually over SSH instead.
  lifecycle {
    ignore_changes = [user_data]
  }
}

# ============================================================================
# MONITORING EC2 INSTANCE
# ============================================================================

resource "aws_instance" "monitoring" {

  ami = data.aws_ami.al2023.id

  instance_type = var.monitoring_instance_type

  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  iam_instance_profile = aws_iam_instance_profile.instance.name

  # IMPORTANT:
  #
  # AWS key pair name = "pro"
  #
  # Local private key file = "pro.pem"
  #
  key_name = var.enable_ssh ? var.key_name : null

  root_block_device {
    volume_size = var.monitoring_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile(
    "${path.module}/monitoring_user_data.sh",
    {
      project_name = var.project_name
    }
  )

  tags = {
    Name = "${var.project_name}-monitoring"
  }

  depends_on = [
    aws_cloudwatch_log_group.app
  ]

  # Same rationale as aws_instance.app: never recreate a live instance just
  # because monitoring_user_data.sh changed.
  lifecycle {
    ignore_changes = [user_data]
  }
}

# ============================================================================
# EC2 STATUS CHECK AUTO RECOVERY
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {

  alarm_name = "${var.project_name}-status-check-failed"

  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 2

  metric_name = "StatusCheckFailed_System"

  namespace = "AWS/EC2"

  period = 60

  statistic = "Maximum"

  threshold = 0

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:recover"
  ]
}

# ============================================================================
# CPU ALARM
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "cpu_high" {

  alarm_name = "${var.project_name}-cpu-high"

  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 5

  metric_name = "CPUUtilization"

  namespace = "AWS/EC2"

  period = 60

  statistic = "Average"

  threshold = 80

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_description = "CPU above 80% for 5 consecutive minutes"
}

# ============================================================================
# MEMORY ALARM
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "mem_high" {

  alarm_name = "${var.project_name}-mem-high"

  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 5

  metric_name = "mem_used_percent"

  namespace = var.project_name

  period = 60

  statistic = "Average"

  threshold = 85

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_description = "Memory above 85% for 5 consecutive minutes"
}

# ============================================================================
# DISK ALARM
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "disk_high" {

  alarm_name = "${var.project_name}-disk-high"

  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 5

  metric_name = "disk_used_percent"

  namespace = var.project_name

  period = 60

  statistic = "Average"

  threshold = 85

  dimensions = {
    InstanceId = aws_instance.app.id
    path       = "/"
  }

  alarm_description = "Disk above 85% for 5 consecutive minutes"
}

# ============================================================================
# CLOUDWATCH DASHBOARD
# ============================================================================

resource "aws_cloudwatch_dashboard" "main" {

  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({

    widgets = [

      # ----------------------------------------------------------------------
      # CPU
      # ----------------------------------------------------------------------

      {
        type = "metric"

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

          view = "timeSeries"

          stacked = false

          region = var.aws_region

          title = "CPU Utilization"
        }
      },

      # ----------------------------------------------------------------------
      # MEMORY
      # ----------------------------------------------------------------------

      {
        type = "metric"

        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {

          metrics = [
            [
              var.project_name,
              "mem_used_percent",
              "InstanceId",
              aws_instance.app.id
            ]
          ]

          view = "timeSeries"

          stacked = false

          region = var.aws_region

          title = "Memory Utilization (%)"
        }
      },

      # ----------------------------------------------------------------------
      # DISK
      # ----------------------------------------------------------------------

      {
        type = "metric"

        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {

          metrics = [
            [
              var.project_name,
              "disk_used_percent",
              "InstanceId",
              aws_instance.app.id,
              "path",
              "/"
            ]
          ]

          view = "timeSeries"

          stacked = false

          region = var.aws_region

          title = "Disk Utilization (%)"
        }
      },

      # ----------------------------------------------------------------------
      # NETWORK
      # ----------------------------------------------------------------------

      {
        type = "metric"

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
              aws_instance.app.id
            ],
            [
              ".",
              "NetworkOut",
              ".",
              "."
            ]
          ]

          view = "timeSeries"

          stacked = false

          region = var.aws_region

          title = "Network Traffic"
        }
      }
    ]
  })
}