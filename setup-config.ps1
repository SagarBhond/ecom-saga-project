$folders = @(
  "config",
  "grafana\provisioning\datasources",
  "grafana\provisioning\dashboards",
  "grafana\dashboards"
)
foreach ($f in $folders) { New-Item -ItemType Directory -Force -Path $f | Out-Null }

@'
# ============================================================================
# Prometheus scrape configuration
# All targets use Docker Compose SERVICE NAMES (not IPs) - this only works
# because prometheus and every target here share the "saga-net" network in
# docker-compose.yml. Do NOT reintroduce IP-based targets here unless
# you go back to the split app/monitoring-instance setup.
# ============================================================================

global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:

  # Prometheus scraping itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Spring Boot services - requires micrometer-registry-prometheus on the
  # classpath and management.endpoints.web.exposure.include=prometheus (or
  # "*") in each service's application.yml/properties, exposing
  # GET /actuator/prometheus
  - job_name: 'order-service'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['order-service:8081']
        labels:
          service: 'order-service'

  - job_name: 'inventory-service'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['inventory-service:8082']
        labels:
          service: 'inventory-service'

  - job_name: 'payment-service'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['payment-service:8083']
        labels:
          service: 'payment-service'

  - job_name: 'notification-service'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['notification-service:8084']
        labels:
          service: 'notification-service'

  # Host-level system metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance_type: 'ec2-monitoring-host'

  - job_name: 'node-exporter-app-host'
    static_configs:
      - targets: ['node-exporter-app:9100']
        labels:
          instance_type: 'ec2-app-host'

  # Per-container resource metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
        labels:
          instance_type: 'monitoring-containers'

  - job_name: 'cadvisor-app-host'
    static_configs:
      - targets: ['cadvisor-app:8080']
        labels:
          instance_type: 'app-containers'
'@ | Set-Content -Path "config\prometheus.yml" -Encoding UTF8

@'
# ============================================================================
# Loki config - single-node, filesystem storage (fine for a demo/small
# deployment). Data is written under /loki, which docker-compose.yml
# mounts to the "loki_data" named volume so it survives container recreation.
# ============================================================================

auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  allow_structured_metadata: false
'@ | Set-Content -Path "config\loki-config.yml" -Encoding UTF8

@'
# ============================================================================
# Promtail config - auto-discovers every running container via the Docker
# socket and ships its logs to Loki. $LOKI_URL is injected from the
# environment via `-config.expand-env=true` in the promtail service's
# "command:" (see docker-compose.yml).
# ============================================================================

server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${LOKI_URL}

scrape_configs:
  - job_name: docker-container-logs
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'compose_service'
      - source_labels: ['__meta_docker_container_id']
        regex: '(.+)'
        target_label: '__path__'
        replacement: /var/lib/docker/containers/$1/$1-json.log
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.+)'
        target_label: 'service'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
      - target_label: 'job'
        replacement: container-logs

    pipeline_stages:
      - json:
          expressions:
            log: log
            stream: stream
            time: time
      - labels:
          stream
      - timestamp:
          source: time
          format: RFC3339Nano
      - output:
          source: log
'@ | Set-Content -Path "config\promtail-config.yml" -Encoding UTF8

@'
# ============================================================================
# Auto-provisions Prometheus and Loki as Grafana datasources on startup.
# URLs use Compose service names since Grafana is on the same saga-net.
# ============================================================================

apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true
'@ | Set-Content -Path "grafana\provisioning\datasources\datasource.yml" -Encoding UTF8

@'
# ============================================================================
# Tells Grafana to watch /etc/grafana/dashboards (mounted from
# ./grafana/dashboards) and auto-load any dashboard JSON files placed there.
# The folder can be empty to start - Grafana just won't show any custom
# dashboards until you add JSON files there (or export one from the UI).
# ============================================================================

apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
'@ | Set-Content -Path "grafana\provisioning\dashboards\dashboard.yml" -Encoding UTF8

@'
# grafana/dashboards

Drop dashboard JSON files here and Grafana will auto-load them on startup
(see grafana/provisioning/dashboards/dashboard.yml). Empty for now - build
dashboards in the Grafana UI (http://localhost:3000) then Export → save the
JSON into this folder to make them persistent/version-controlled.
'@ | Set-Content -Path "grafana\dashboards\README.md" -Encoding UTF8

Write-Host "Done. Verifying:"
Get-ChildItem -Recurse config, grafana | Select-Object FullName