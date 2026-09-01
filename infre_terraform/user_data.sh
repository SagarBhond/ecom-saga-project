#!/bin/bash
# Bootstraps Docker + Docker Compose + App Stack + CloudWatch Agent on first boot.
set -euo pipefail

dnf update -y
dnf install -y docker git curl amazon-cloudwatch-agent

# AL2023 may not expose amazon-ssm-agent in the configured repositories.
if ! dnf install -y amazon-ssm-agent; then
  curl -fsSL "https://s3.${aws_region}.amazonaws.com/amazon-ssm-${aws_region}/latest/linux_amd64/amazon-ssm-agent.rpm" \
    -o /tmp/amazon-ssm-agent.rpm
  dnf install -y /tmp/amazon-ssm-agent.rpm
fi

systemctl enable --now docker
systemctl enable --now amazon-ssm-agent
usermod -aG docker ec2-user

# Docker Compose v2 plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Minimal CloudWatch Agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "metrics": {
    "namespace": "${project_name}",
    "metrics_collected": {
      "cpu": { "measurement": ["cpu_usage_active"], "totalcpu": true },
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"] }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/lib/docker/containers/*/*.log",
            "log_group_name": "/${project_name}/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Add swap file for memory safety
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Clone repo
mkdir -p /home/ec2-user/app
if [ ! -d /home/ec2-user/app/.git ]; then
  git clone https://github.com/SagarBhond/ecom-saga-project.git /home/ec2-user/app
fi

cd /home/ec2-user/app
git fetch origin
git checkout main
git reset --hard origin/main

if [ ! -f .env ]; then cp .env.example .env; fi
chmod +x scripts/*.sh

# Configure Promtail to ship logs to the monitoring instance
./scripts/configure-monitoring-ips.sh app

# Start the App Stack
/usr/local/bin/docker-compose -f docker-compose.yml -f infre_terraform/docker-compose.prod.yml up -d

echo "Bootstrap complete." > /var/log/bootstrap-done.log