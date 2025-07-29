#!/bin/bash

echo "Applying OpenTelemetry Collector enhanced configuration..."
kubectl apply -f /Users/seanwiley/workshop/templates/otel_demo_grafana_fix.yaml

echo "Waiting for configuration to be applied..."
sleep 10

echo "Restarting OpenTelemetry Collector to apply new configuration..."
kubectl rollout restart deployment/otel-demo-otelcol -n otel-demo

echo "Waiting for OpenTelemetry Collector to be ready..."
kubectl rollout status deployment/otel-demo-otelcol -n otel-demo --timeout=120s

echo "✅ OpenTelemetry Grafana dashboards fix has been applied!"
echo "Please wait a few minutes for metrics to be collected and then refresh the Grafana dashboards."
echo
echo "You can access the OpenTelemetry Demo Grafana at: http://localhost:3001"
