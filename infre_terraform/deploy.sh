#!/bin/bash
set -e

PROJECT_DIR="/home/ec2-user/ecom-saga-project"
REPO_URL="https://github.com/SagarBhond/ecom-saga-project.git"

echo "=== STARTING DOCKER ==="
sudo systemctl enable --now docker

echo "=== INSTALLING REQUIREMENTS ==="
sudo dnf install -y git curl

echo "=== INSTALLING DOCKER COMPOSE ==="
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fL https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "=== INSTALLING BUILDX ==="
sudo curl -fL https://github.com/docker/buildx/releases/download/v0.36.1/buildx-v0.36.1.linux-amd64 -o /usr/local/lib/docker/cli-plugins/docker-buildx
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

echo "=== VERSIONS ==="
docker compose version
docker buildx version

echo "=== CLONING PROJECT ==="
sudo rm -rf "$PROJECT_DIR"
sudo git clone "$REPO_URL" "$PROJECT_DIR"
sudo chown -R ec2-user:ec2-user "$PROJECT_DIR"

cd "$PROJECT_DIR"

echo "=== VALIDATING COMPOSE ==="
docker compose -f docker-compose.yml config

echo "=== STARTING APPLICATION ==="
docker compose -f docker-compose.yml down || true
docker compose -f docker-compose.yml up -d --build

echo "=== WAITING FOR SERVICES ==="
sleep 20

echo "=== FINAL STATUS ==="
docker compose -f docker-compose.yml ps
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "======================================"
echo " ECOM SAGA DEPLOYMENT COMPLETED"
echo "======================================"
