#!/bin/bash
# ============================================================================
# monitoring_user_data.sh — Monitoring EC2 bootstrap
# Rendered by Terraform's templatefile() with one variable: project_name.
# Installs Docker, discovers the Application EC2's private IP by tag,
# patches config/prometheus.yml to scrape it (since these are two separate
# hosts, not one shared Docker network), and starts Grafana + Prometheus + Loki
# — using docker-compose.yml, limited to just the monitoring-side
# services (see step 6 below).
#
# NOTE: only ${project_name} below is a Terraform template variable. Every
# other $VAR in this file is plain bash and deliberately brace-free so
# Terraform's templatefile() doesn't try to interpolate it.
# ============================================================================

set -e
exec > /var/log/user-data.log 2>&1

PROJECT_NAME="${project_name}"
<<<<<<< HEAD
REPO_URL="https://github.com/shravaneeghatol/ecom-saga-project.git"
=======
REPO_URL="https://github.com/SagarBhond/ecom-saga-project.git"
>>>>>>> 4e7f136 (Update E-Commerce Saga project)
BRANCH="main"
APP_DIR="/home/ec2-user/app"

echo "=== Bootstrapping monitoring instance for project: $PROJECT_NAME ==="

# ---- 1. OS packages ---------------------------------------------------
dnf update -y
dnf install -y docker git jq unzip

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -sSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

if ! command -v aws >/dev/null 2>&1; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl start amazon-ssm-agent 2>/dev/null || true

dnf install -y amazon-cloudwatch-agent || true
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONF'
{
  "metrics": {
    "namespace": "PROJECT_NAME_PLACEHOLDER-monitoring",
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"] }
    }
  }
}
CWCONF
sed -i "s/PROJECT_NAME_PLACEHOLDER/$PROJECT_NAME/" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true

# ---- 2. Resolve region via IMDSv2 --------------------------------------
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

# ---- 3. Discover the application instance's private IP by tag ----------
APP_IP=""
for i in $(seq 1 30); do
  APP_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$PROJECT_NAME-app" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].PrivateIpAddress" \
    --output text 2>/dev/null || echo "")
  if [ -n "$APP_IP" ] && [ "$APP_IP" != "None" ]; then
    echo "Found application instance IP: $APP_IP"
    break
  fi
  echo "Waiting for application instance to appear... ($i/30)"
  sleep 10
done

# ---- 4. Clone the repo --------------------------------------------------
if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

# ---- 5. Patch Prometheus scrape targets with the app instance's IP ------
# config/prometheus.yml (as generated for the single-host setup) scrapes by
# Docker Compose service name, which only resolves on a shared network.
# These two instances are separate hosts, so rewrite targets to the app IP.
if [ -n "$APP_IP" ] && [ "$APP_IP" != "None" ]; then
  git checkout -- config/prometheus.yml
  sed -i \
    -e "s/order-service:8081/$APP_IP:8081/g" \
    -e "s/inventory-service:8082/$APP_IP:8082/g" \
    -e "s/payment-service:8083/$APP_IP:8083/g" \
    -e "s/notification-service:8084/$APP_IP:8084/g" \
    -e "s/node-exporter:9100/$APP_IP:9100/g" \
    -e "s/cadvisor:8080/$APP_IP:8080/g" \
    config/prometheus.yml
else
  echo "WARNING: could not resolve app instance IP — prometheus.yml left unpatched, scrapes will fail."
fi

# ---- 6. Start Grafana + Prometheus + Loki ----------------------------------
# Uses docker-compose.yml but only brings up the monitoring-side
# services — Kafka and the 4 app services stay on the app instance (see
# user_data.sh). --force-recreate matches local testing behavior.
docker compose -f docker-compose.yml up -d --force-recreate \
  prometheus loki grafana

echo "--- docker compose ps ---"
docker compose -f docker-compose.yml ps

echo "=== Monitoring EC2 bootstrap complete ==="
echo "Grafana:    http://<this-instance-public-ip>:3000  (admin/admin by default)"
echo "Prometheus: http://<this-instance-public-ip>:9090"
echo "Loki:       http://<this-instance-public-ip>:3100"
