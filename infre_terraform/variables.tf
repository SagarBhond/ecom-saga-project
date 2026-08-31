variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type for application server."
  type        = string
  default     = "t3.small"
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for monitoring server."
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
  description = "Enable SSH access."
  type        = bool
  default     = true
}

variable "key_name" {
  description = "AWS EC2 key pair name. Do not include .pem."
  type        = string
  default     = "pro"
}

variable "expose_kafka_ui" {
  description = "Allow Kafka UI access."
  type        = bool
  default     = true
}

variable "expose_grafana" {
  description = "Allow Grafana access."
  type        = bool
  default     = true
}

variable "expose_prometheus" {
  description = "Allow Prometheus access."
  type        = bool
  default     = false
}

variable "expose_loki" {
  description = "Allow Loki access."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 14
}

variable "project_name" {
  description = "Project name."
  type        = string
  default     = "ecom-saga"
}

variable "my_ip_cidr" {
  description = "Public IP CIDR allowed for SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "aws_access_key" {
  description = "Optional AWS access key ID. If set, Terraform uses static credentials instead of the default credential chain."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "Optional AWS secret access key. If set, Terraform uses static credentials instead of the default credential chain."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  description = "Optional AWS session token for temporary credentials."
  type        = string
  default     = ""
  sensitive   = true
}

variable "app_base_url" {
  description = "Optional base URL override for generated Swagger and API URLs. For local testing, set this to http://localhost."
  type        = string
  default     = ""
}