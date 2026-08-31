# E-Commerce Saga Microservices — AWS EC2 Deployment

This repository contains a Spring Boot choreography-based saga application with four microservices:

- order-service
- inventory-service
- payment-service
- notification-service

The project includes Docker Compose for local development and a Terraform setup for AWS EC2 deployment. GitHub Actions builds the services, pushes the Docker images to Docker Hub, and deploys the stack to EC2 over SSH.

## Terraform and deployment notes

- The active Terraform configuration is under `infre_terraform/`.
- The duplicate `terraform/` directory was removed to avoid drift and conflicting AWS resources.
- The deployment scripts target `/home/ec2-user/ecom-saga-project` so the project directory is consistently owned by `ec2-user`.
- SSH-based deployment is used because the EC2 instance does not expose a working SSM host connection in practice.
- The Terraform stack now prefers static AWS credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) and disables the GitHub OIDC role by default.
- For local Terraform runs, set `app_base_url = "http://localhost"` if you want Swagger URLs to display as `http://localhost:8081/swagger-ui/index.html#/order-controller/create`.

## Typical validation commands

```powershell
cd infre_terraform
terraform init -backend=false
terraform validate
```

## GitHub Actions

The repo includes the following workflows:

- `.github/workflows/ci.yml` — build and test each Java service
- `.github/workflows/deploy.yml` — SSH deployment to EC2
- `.github/workflows/ci-cd-pipeline.yml` — end-to-end CI/CD pipeline

## Required GitHub secrets

- `DOCKERHUB_TOKEN`
- `EC2_HOST`
- `EC2_USER`
- `EC2_SSH_KEY`

The EC2 private key must never be committed to Git.
