# OIDC-based GitHub deployment is intentionally disabled in this Terraform stack.
# This project uses AWS static credentials (access key + secret key) instead of
# GitHub OIDC. Set the values in the AWS provider environment variables or in the
# `aws_access_key` / `aws_secret_key` Terraform variables before running `terraform apply`.
