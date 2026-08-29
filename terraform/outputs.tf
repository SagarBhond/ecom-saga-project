# ============================================================
# APPLICATION EC2 OUTPUTS
# ============================================================

output "instance_id" {
  description = "EC2 instance ID of the application server. Used by GitHub Actions SSM deployment."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IPv4 address of the application EC2 instance."
  value       = aws_instance.app.public_ip
}

output "private_ip" {
  description = "Private IPv4 address of the application EC2 instance."
  value       = aws_instance.app.private_ip
}

# ============================================================
# SSH CONNECTION
# ============================================================

output "ssh_command" {
  description = "SSH command for connecting to the application EC2 instance."

  value = var.enable_ssh ? (
    "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.app.public_ip}"
  ) : (
    "aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}"
  )
}

# ============================================================
# APPLICATION SERVICE URLS
# ============================================================

output "service_urls" {
  description = "REST API URLs for the E-Commerce Saga services."

  value = {
    order_service = "http://${aws_instance.app.public_ip}:8081/api/orders"

    inventory_service = "http://${aws_instance.app.public_ip}:8082/api/inventory"

    payment_service = "http://${aws_instance.app.public_ip}:8083"

    notification_service = "http://${aws_instance.app.public_ip}:8084/api/notifications"
  }
}

# ============================================================
# SWAGGER UI URLS
# ============================================================

output "swagger_ui_urls" {
  description = "Swagger UI URLs for the E-Commerce Saga services."

  value = {
    order_service = "http://${aws_instance.app.public_ip}:8081/swagger-ui.html"

    inventory_service = "http://${aws_instance.app.public_ip}:8082/swagger-ui.html"

    payment_service = "http://${aws_instance.app.public_ip}:8083/swagger-ui.html"

    notification_service = "http://${aws_instance.app.public_ip}:8084/swagger-ui.html"
  }
}

# ============================================================
# KAFKA UI
# ============================================================

output "kafka_ui_url" {
  description = "Kafka UI URL."

  value = var.expose_kafka_ui ? (
    "http://${aws_instance.app.public_ip}:8090"
  ) : (
    "Kafka UI access disabled"
  )
}

# ============================================================
# MONITORING EC2 OUTPUTS
# ============================================================

output "monitoring_instance_id" {
  description = "Monitoring EC2 instance ID."

  value = aws_instance.monitoring.id
}

output "monitoring_public_ip" {
  description = "Public IPv4 address of the monitoring EC2 instance."

  value = aws_instance.monitoring.public_ip
}

output "monitoring_private_ip" {
  description = "Private IPv4 address of the monitoring EC2 instance."

  value = aws_instance.monitoring.private_ip
}

# ============================================================
# OBSERVABILITY URLS
# ============================================================

output "observability_urls" {
  description = "URLs for the monitoring and observability stack."

  value = {
    grafana = var.expose_grafana ? (
      "http://${aws_instance.monitoring.public_ip}:3000"
    ) : (
      "Grafana access disabled"
    )

    prometheus = var.expose_prometheus ? (
      "http://${aws_instance.monitoring.public_ip}:9090"
    ) : (
      "Prometheus access disabled"
    )

    loki = var.expose_loki ? (
      "http://${aws_instance.monitoring.public_ip}:3100"
    ) : (
      "Loki access disabled"
    )
  }
}

# ============================================================
# CLOUDWATCH
# ============================================================

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group used by the application."

  value = aws_cloudwatch_log_group.app.name
}

# ============================================================
# TERRAFORM RUNNER PUBLIC IP
# ============================================================

output "terraform_runner_ip" {
  description = "Public IP detected automatically by Terraform and used for restricted administrative access."

  value = local.my_ip_cidr
}