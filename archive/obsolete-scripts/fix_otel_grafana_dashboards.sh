#!/bin/bash

echo "Starting OpenTelemetry Grafana dashboard fix..."

# Extract the current configuration
echo "Extracting current OpenTelemetry Collector configuration..."
kubectl get configmap -n otel-demo otel-demo-otelcol -o yaml > /tmp/current-otel-config.yaml

# Save the original config in case we need to restore it
echo "Backing up original configuration..."
cp /tmp/current-otel-config.yaml /tmp/otel-collector-backup.yaml

# Create a new complete configuration file
echo "Creating complete configuration with spanmetrics connector..."
cat > /tmp/complete-config.yaml << 'EOF'
connectors:
  spanmetrics:
    namespace: "traces.span.metrics"
    aggregation_temporality: AGGREGATION_TEMPORALITY_CUMULATIVE
    metrics_flush_interval: 15s
    dimensions:
      - name: service.name
        default: unknown_service
      - name: span.name
        default: unknown_operation
      - name: span.kind
        default: SPAN_KIND_UNSPECIFIED
      - name: status.code
        default: STATUS_CODE_UNSET
      # Removed duplicate dimensions http.method and http.status_code
    histogram:
      explicit:
        buckets: [100us, 1ms, 2ms, 6ms, 10ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]
exporters:
  debug: {}
  opensearch:
    http:
      endpoint: http://otel-demo-opensearch:9200
      tls:
        insecure: true
  otlp:
    endpoint: 'otel-demo-jaeger-collector:4317'
    tls:
      insecure: true
  otlphttp/prometheus:
    endpoint: http://otel-demo-prometheus-server:9090/api/v1/otlp
    tls:
      insecure: true
  prometheus:
    endpoint: 0.0.0.0:8889
    resource_to_telemetry_conversion:
      enabled: true
extensions:
  health_check:
    endpoint: ${env:MY_POD_IP}:13133
processors:
  batch: {}
  k8sattributes:
    extract:
      metadata:
      - k8s.namespace.name
      - k8s.deployment.name
      - k8s.statefulset.name
      - k8s.daemonset.name
      - k8s.cronjob.name
      - k8s.job.name
      - k8s.pod.name
      - k8s.pod.uid
      - k8s.node.name
    passthrough: false
    pod_association:
    - sources:
      - from: resource_attribute
        name: k8s.pod.ip
    - sources:
      - from: resource_attribute
        name: k8s.pod.uid
    - sources:
      - from: connection
  memory_limiter:
    check_interval: 1s
    limit_mib: 400
    limit_percentage: 80
    spike_limit_mib: 100
    spike_limit_percentage: 25
  resource:
    attributes:
    - action: insert
      from_attribute: k8s.pod.uid
      key: service.instance.id
  transform:
    error_mode: ignore
    trace_statements:
    - context: span
      statements:
      - replace_pattern(name, "\\?.*", "")
      - replace_match(name, "GET /api/products/*", "GET /api/products/{productId}")
    metric_statements:
      - context: datapoint
        statements:
          - set(attributes["collector"], "otel-collector")
receivers:
  httpcheck/frontendproxy:
    targets:
    - endpoint: http://otel-demo-frontendproxy:8080
  jaeger:
    protocols:
      grpc:
        endpoint: ${env:MY_POD_IP}:14250
      thrift_compact:
        endpoint: ${env:MY_POD_IP}:6831
      thrift_http:
        endpoint: ${env:MY_POD_IP}:14268
  otlp:
    protocols:
      grpc:
        endpoint: ${env:MY_POD_IP}:4317
      http:
        cors:
          allowed_origins:
          - http://*
          - https://*
        endpoint: ${env:MY_POD_IP}:4318
  prometheus:
    config:
      scrape_configs:
      - job_name: opentelemetry-collector
        scrape_interval: 10s
        static_configs:
        - targets:
          - ${env:MY_POD_IP}:8888
  redis:
    collection_interval: 10s
    endpoint: otel-demo-valkey:6379
  zipkin:
    endpoint: ${env:MY_POD_IP}:9411
service:
  extensions:
  - health_check
  pipelines:
    logs:
      exporters:
      - opensearch
      - debug
      processors:
      - memory_limiter
      - k8sattributes
      - resource
      - batch
      receivers:
      - otlp
    metrics:
      exporters:
      - prometheus
      - debug
      processors:
      - memory_limiter
      - k8sattributes
      - resource
      - transform
      - batch
      receivers:
      - otlp
      - spanmetrics
    traces:
      exporters:
      - otlp
      - spanmetrics
      processors:
      - memory_limiter
      - k8sattributes
      - resource
      - transform
      - batch
      receivers:
      - otlp
  telemetry:
    metrics:
      address: ${env:MY_POD_IP}:8888
EOF

# Back up the existing ConfigMap before making changes
echo "Backing up existing ConfigMap..."
kubectl get configmap -n otel-demo otel-demo-otelcol -o yaml > /tmp/otel-collector-backup.yaml

# Create a ConfigMap with the complete configuration
echo "Creating ConfigMap with complete configuration..."
kubectl create configmap -n otel-demo otel-demo-otelcol --from-file=relay=/tmp/complete-config.yaml --dry-run=client -o yaml > /tmp/new-configmap.yaml

# Apply the new ConfigMap
echo "Applying complete configuration..."
kubectl apply -f /tmp/new-configmap.yaml

# Verify the ConfigMap was applied successfully
if [ $? -ne 0 ]; then
  echo "Failed to apply new ConfigMap. Restoring backup..."
  kubectl apply -f /tmp/otel-collector-backup.yaml
  exit 1
fi

echo "Restarting OpenTelemetry Collector to apply changes..."
kubectl rollout restart deployment/otel-demo-otelcol -n otel-demo

echo "Waiting for OpenTelemetry Collector to be ready..."
kubectl rollout status deployment/otel-demo-otelcol -n otel-demo --timeout=60s || true

# Check if the pod is running after restart
echo "Checking if OpenTelemetry Collector is running..."
sleep 5
POD_STATUS=$(kubectl get pods -n otel-demo -l app.kubernetes.io/name=otelcol -o jsonpath='{.items[0].status.phase}' 2>/dev/null)

# Check if the pod is running after restart
echo "Checking if OpenTelemetry Collector is running..."
sleep 10  # Give it a bit more time to stabilize
POD_STATUS=$(kubectl get pods -n otel-demo -l app.kubernetes.io/name=otelcol -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
POD_READY=$(kubectl get pods -n otel-demo -l app.kubernetes.io/name=otelcol -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

if [ "$POD_STATUS" != "Running" ] || [ "$POD_READY" != "true" ]; then
  echo "OpenTelemetry Collector is not running properly. Checking logs..."
  kubectl logs -n otel-demo -l app.kubernetes.io/name=otelcol --tail=30 || echo "Could not retrieve logs"
  
  echo "Trying a simpler approach with minimal changes..."
  echo "Restoring original configuration and applying minimal patch..."
  
  # Restore the original configuration
  kubectl apply -f /tmp/otel-collector-backup.yaml
  
  # Create a minimal patch that only adds resource_to_telemetry_conversion and spanmetrics connector
  cat > /tmp/minimal-patch.json << 'EOF'
{
  "data": {
    "relay": "connectors:\n  spanmetrics:\n    namespace: \"traces.span.metrics\"\n    aggregation_temporality: AGGREGATION_TEMPORALITY_CUMULATIVE\n    metrics_flush_interval: 15s\n    dimensions:\n      - name: service.name\n        default: unknown_service\n      - name: span.name\n        default: unknown_operation\n      - name: span.kind\n        default: SPAN_KIND_UNSPECIFIED\n      - name: status.code\n        default: STATUS_CODE_UNSET\n    histogram:\n      explicit:\n        buckets: [100us, 1ms, 2ms, 6ms, 10ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]\nexporters:\n  prometheus:\n    resource_to_telemetry_conversion:\n      enabled: true\nservice:\n  pipelines:\n    metrics:\n      receivers: [otlp, spanmetrics]\n    traces:\n      exporters: [otlp, spanmetrics]\n"
  }
}
EOF

  # Apply the minimal patch
  kubectl patch configmap -n otel-demo otel-demo-otelcol --type=merge --patch-file /tmp/minimal-patch.json
  kubectl rollout restart deployment/otel-demo-otelcol -n otel-demo
  echo "Waiting for OpenTelemetry Collector to be ready after minimal patch..."
  kubectl rollout status deployment/otel-demo-otelcol -n otel-demo --timeout=60s || true
  
  # Check again if the pod is running
  sleep 10
  POD_STATUS=$(kubectl get pods -n otel-demo -l app.kubernetes.io/name=otelcol -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
  if [ "$POD_STATUS" != "Running" ]; then
    echo "⚠️ Warning: OpenTelemetry Collector is still not running properly."
    echo "Please check the logs manually with: kubectl logs -n otel-demo -l app.kubernetes.io/name=otelcol"
  else
    echo "✅ OpenTelemetry Collector is now running with minimal configuration changes."
  fi
fi

# Create a Grafana dashboard for spanmetrics
echo "Creating Grafana dashboard for spanmetrics..."
cat > /tmp/spanmetrics-dashboard.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-demo-grafana-spanmetrics-dashboard
  namespace: otel-demo
  labels:
    grafana_dashboard: "1"
data:
  spanmetrics-dashboard.json: |
    {
      "annotations": {
        "list": [
          {
            "builtIn": 1,
            "datasource": {
              "type": "grafana",
              "uid": "-- Grafana --"
            },
            "enable": true,
            "hide": true,
            "iconColor": "rgba(0, 211, 255, 1)",
            "name": "Annotations & Alerts",
            "type": "dashboard"
          }
        ]
      },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 0,
      "id": 1,
      "links": [],
      "liveNow": false,
      "panels": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "webstore-metrics"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 0,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "linear",
                "lineWidth": 1,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "auto",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "red",
                    "value": 80
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 0,
            "y": 0
          },
          "id": 1,
          "options": {
            "legend": {
              "calcs": [],
              "displayMode": "list",
              "placement": "bottom",
              "showLegend": true
            },
            "tooltip": {
              "mode": "single",
              "sort": "none"
            }
          },
          "targets": [
            {
              "datasource": {
                "type": "prometheus",
                "uid": "webstore-metrics"
              },
              "editorMode": "builder",
              "expr": "sum(rate(traces_span_metrics_calls_total[5m])) by (service_name, span_name)",
              "instant": false,
              "range": true,
              "refId": "A"
            }
          ],
          "title": "Span Count Rate by Service and Operation",
          "type": "timeseries"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "webstore-metrics"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 0,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "linear",
                "lineWidth": 1,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "auto",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "red",
                    "value": 80
                  }
                ]
              },
              "unit": "s"
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 12,
            "y": 0
          },
          "id": 2,
          "options": {
            "legend": {
              "calcs": [],
              "displayMode": "list",
              "placement": "bottom",
              "showLegend": true
            },
            "tooltip": {
              "mode": "single",
              "sort": "none"
            }
          },
          "targets": [
            {
              "datasource": {
                "type": "prometheus",
                "uid": "webstore-metrics"
              },
              "editorMode": "builder",
              "expr": "histogram_quantile(0.95, sum(rate(traces_span_metrics_duration_bucket[5m])) by (le, service_name, span_name))",
              "instant": false,
              "range": true,
              "refId": "A"
            }
          ],
          "title": "p95 Latency by Service and Operation",
          "type": "timeseries"
        }
      ],
      "refresh": "5s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": [],
      "templating": {
        "list": []
      },
      "time": {
        "from": "now-15m",
        "to": "now"
      },
      "timepicker": {},
      "timezone": "",
      "title": "Spanmetrics Demo Dashboard",
      "uid": "spanmetrics-demo",
      "version": 1,
      "weekStart": ""
    }
EOF

kubectl apply -f /tmp/spanmetrics-dashboard.yaml

echo "✅ OpenTelemetry Grafana dashboards fix has been applied!"
echo "Please wait 3-5 minutes for metrics to be collected and then refresh the Grafana dashboards."
echo
echo "You can access the OpenTelemetry Demo Grafana at: http://localhost:3001"