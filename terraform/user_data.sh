#!/bin/bash

# ============================================================================
# user_data.sh — Application EC2 bootstrap
# ============================================================================

set -e

exec > /var/log/user-data.log 2>&1

# IMPORTANT:
# ${project_name} is a Terraform template variable.
# All other $${...} variables are Bash variables and MUST use $${...}
# so Terraform templatefile() does not try to process them.

PROJECT_NAME="${project_name}"

REPO_URL="https://github.com/SagarBhond/ecom-saga-project.git"
BRANCH="main"
APP_DIR="/home/ec2-user/app"

echo "=============================================="
echo "Bootstrapping application EC2"
echo "Project: $PROJECT_NAME"
echo "=============================================="

# ============================================================================
# 1. UPDATE SYSTEM AND INSTALL REQUIRED PACKAGES
# ============================================================================

echo "Installing required packages..."

dnf update -y

dnf install -y \
  docker \
  git \
  jq \
  unzip \
  curl

# ============================================================================
# 2. START DOCKER
# ============================================================================

echo "Starting Docker..."

systemctl enable docker
systemctl start docker

usermod -aG docker ec2-user

# ============================================================================
# 3. INSTALL DOCKER COMPOSE V2
# ============================================================================

echo "Installing Docker Compose..."

mkdir -p /usr/local/lib/docker/cli-plugins

curl -L \
  "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose

chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "Docker version:"
docker --version

echo "Docker Compose version:"
docker compose version

# ============================================================================
# 4. INSTALL AWS CLI
# ============================================================================

echo "Checking AWS CLI..."

if ! command -v aws >/dev/null 2>&1; then

  echo "Installing AWS CLI..."

  curl -s \
    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o /tmp/awscliv2.zip

  rm -rf /tmp/aws

  unzip -q \
    /tmp/awscliv2.zip \
    -d /tmp

  /tmp/aws/install

fi

echo "AWS CLI:"
aws --version

# ============================================================================
# 5. START SSM AGENT
# ============================================================================

echo "Starting SSM Agent..."

systemctl enable amazon-ssm-agent 2>/dev/null || true

systemctl start amazon-ssm-agent 2>/dev/null || true

# ============================================================================
# 6. CLOUDWATCH AGENT
# ============================================================================

echo "Installing CloudWatch Agent..."

dnf install -y amazon-cloudwatch-agent || true

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONF'
{
  "metrics": {
    "namespace": "PROJECT_NAME_PLACEHOLDER-app",
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "resources": [
          "/"
        ]
      }
    }
  }
}
CWCONF

sed -i \
  "s/PROJECT_NAME_PLACEHOLDER/$PROJECT_NAME/" \
  /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  || true

# ============================================================================
# 7. GET AWS REGION USING IMDSv2
# ============================================================================

echo "Detecting AWS region..."

TOKEN=$(curl -s -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

REGION=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/placement/region")

if [ -z "$REGION" ]; then
  echo "ERROR: Could not determine AWS region."
  exit 1
fi

echo "AWS Region: $REGION"

# ============================================================================
# 8. FIND MONITORING EC2 PRIVATE IP
# ============================================================================

echo "Searching for monitoring EC2 instance..."

MONITORING_IP=""

for i in $(seq 1 30); do

  echo "Attempt $i/30..."

  MONITORING_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=tag:Name,Values=$PROJECT_NAME-monitoring" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].PrivateIpAddress" \
    --output text \
    2>/dev/null || echo "")

  if [ -n "$MONITORING_IP" ] && [ "$MONITORING_IP" != "None" ]; then

    echo "Monitoring EC2 found."
    echo "Monitoring Private IP: $MONITORING_IP"

    break

  fi

  echo "Monitoring EC2 not available yet."

  sleep 10

done

if [ -z "$MONITORING_IP" ] || [ "$MONITORING_IP" = "None" ]; then

  echo "WARNING: Monitoring EC2 was not found."

else

  echo "Monitoring IP: $MONITORING_IP"

fi

# ============================================================================
# 9. CLONE APPLICATION REPOSITORY
# ============================================================================

echo "Preparing application directory..."

if [ ! -d "$APP_DIR/.git" ]; then

  echo "Cloning repository..."

  rm -rf "$APP_DIR"

  git clone \
    "$REPO_URL" \
    "$APP_DIR"

fi

cd "$APP_DIR"

echo "Application directory:"
pwd

# ============================================================================
# 10. CHECKOUT MAIN BRANCH
# ============================================================================

echo "Updating repository..."

git fetch origin

git checkout "$BRANCH"

git reset --hard "origin/$BRANCH"

# ============================================================================
# 11. CREATE ENVIRONMENT FILE
# ============================================================================

echo "Checking .env file..."

if [ ! -f ".env" ]; then

  if [ -f ".env.example" ]; then

    cp .env.example .env

    echo ".env created from .env.example"

  else

    echo "WARNING: .env.example does not exist."

  fi

fi

# ============================================================================
# 12. UPDATE LOKI URL
# ============================================================================

if [ -n "$MONITORING_IP" ] && [ "$MONITORING_IP" != "None" ]; then

  echo "Configuring Loki URL..."

  if [ -f ".env" ]; then

    sed -i '/^LOKI_URL=/d' .env

    echo "LOKI_URL=http://$MONITORING_IP:3100/loki/api/v1/push" >> .env

  fi

fi

# ============================================================================
# 13. SHOW DOCKER INFORMATION
# ============================================================================

echo "=============================================="
echo "Docker information"
echo "=============================================="

docker --version
docker compose version

echo "Logged-in Docker registries:"
docker info 2>/dev/null | grep -i username || true

# ============================================================================
# 14. DOCKER HUB LOGIN
# ============================================================================
#
# IMPORTANT:
#
# The EC2 instance should NOT contain your Docker Hub password/token
# inside this user_data.sh file.
#
# Your Docker Hub repositories must be PUBLIC for this deployment approach,
# OR the EC2 instance must have a secure Docker Hub credential configured.
#
# If repositories are private, configure Docker Hub authentication separately.
#

echo "Checking Docker Hub access..."

# ============================================================================
# 15. CHECK DOCKER COMPOSE FILE
# ============================================================================

if [ ! -f "docker-compose.yml" ]; then

  echo "ERROR: docker-compose.yml not found."

  ls -la

  exit 1

fi

echo "docker-compose.yml found."

# ============================================================================
# 16. VALIDATE DOCKER COMPOSE
# ============================================================================

echo "Validating Docker Compose..."

docker compose \
  -f docker-compose.yml \
  config

# ============================================================================
# 17. PULL REQUIRED IMAGES
# ============================================================================

echo "Pulling Docker images..."

docker compose \
  -f docker-compose.yml \
  pull \
  kafka \
  kafka-ui \
  order-service \
  inventory-service \
  payment-service \
  notification-service \
  node-exporter \
  cadvisor \
  promtail \
  || true

# ============================================================================
# 18. START APPLICATION
# ============================================================================

echo "Starting application stack..."

docker compose \
  -f docker-compose.yml \
  up -d \
  --force-recreate \
  kafka \
  kafka-ui \
  order-service \
  inventory-service \
  payment-service \
  notification-service \
  node-exporter \
  cadvisor \
  promtail

# ============================================================================
# 19. SHOW CONTAINERS
# ============================================================================

echo "=============================================="
echo "Docker Compose Status"
echo "=============================================="

docker compose \
  -f docker-compose.yml \
  ps

# ============================================================================
# 20. WAIT FOR APPLICATION SERVICES
# ============================================================================

echo "Waiting for Spring Boot services..."

ORDER_HEALTHY=false
INVENTORY_HEALTHY=false
PAYMENT_HEALTHY=false
NOTIFICATION_HEALTHY=false

for i in $(seq 1 30); do

  echo "Health check attempt $i/30"

  if curl -sf \
    "http://localhost:8081/actuator/health" \
    >/dev/null 2>&1; then

    ORDER_HEALTHY=true
    echo "Order service: HEALTHY"

  else

    echo "Order service: NOT READY"

  fi


  if curl -sf \
    "http://localhost:8082/actuator/health" \
    >/dev/null 2>&1; then

    INVENTORY_HEALTHY=true
    echo "Inventory service: HEALTHY"

  else

    echo "Inventory service: NOT READY"

  fi


  if curl -sf \
    "http://localhost:8083/actuator/health" \
    >/dev/null 2>&1; then

    PAYMENT_HEALTHY=true
    echo "Payment service: HEALTHY"

  else

    echo "Payment service: NOT READY"

  fi


  if curl -sf \
    "http://localhost:8084/actuator/health" \
    >/dev/null 2>&1; then

    NOTIFICATION_HEALTHY=true
    echo "Notification service: HEALTHY"

  else

    echo "Notification service: NOT READY"

  fi


  if [ "$ORDER_HEALTHY" = true ] \
    && [ "$INVENTORY_HEALTHY" = true ] \
    && [ "$PAYMENT_HEALTHY" = true ] \
    && [ "$NOTIFICATION_HEALTHY" = true ]; then

    echo "=============================================="
    echo "ALL APPLICATION SERVICES ARE HEALTHY"
    echo "=============================================="

    break

  fi

  sleep 10

done

# ============================================================================
# 21. FINAL STATUS
# ============================================================================

echo "=============================================="
echo "FINAL DOCKER STATUS"
echo "=============================================="

docker compose \
  -f docker-compose.yml \
  ps

echo "=============================================="
echo "APPLICATION EC2 BOOTSTRAP COMPLETE"
echo "=============================================="