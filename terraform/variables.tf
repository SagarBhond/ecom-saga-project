variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type for the application server."
  type        = string
  default     = "t3.small"
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for the monitoring server."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size for application EC2."
  type        = number
  default     = 30
}

variable "monitoring_volume_size_gb" {
  description = "Root EBS volume size for monitoring EC2."
  type        = number
  default     = 30
}

variable "enable_ssh" {
  description = "Enable SSH access from the automatically detected public IP."
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Existing AWS EC2 key pair name."
  type        = string
  default     = "pro"
}

variable "expose_kafka_ui" {
  description = "Allow Kafka UI access from the automatically detected public IP."
  type        = bool
  default     = true
}

variable "expose_grafana" {
  description = "Allow Grafana access from the automatically detected public IP."
  type        = bool
  default     = true
}

variable "expose_prometheus" {
  description = "Allow Prometheus access from the automatically detected public IP."
  type        = bool
  default     = false
}

variable "expose_loki" {
  description = "Allow Loki access from the automatically detected public IP."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days."
  type        = number
  default     = 14
}

variable "project_name" {
  description = "Project name used for AWS resource names and tags."
  type        = string
  default     = "instance-ecom-saga"
}