#!/bin/bash
#
# OpenTelemetry Demo Deployment Script
# Deploys the OpenTelemetry demo application to existing cluster
#

set -Eeuo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/ui.sh"

# Default configuration
CLUSTER_NAME=""
NAMESPACE="otel-demo"
HELM_CHART_VERSION="0.30.0"
ENABLE_JAEGER=true
ENABLE_PROMETHEUS=true

# Function to show help
show_help() {
    help_header \
        "" \
        "Deploys the OpenTelemetry demo application to an existing EKS cluster.\nIncludes all microservices and observability components."
    cat << EOF

OPTIONS:
  --cluster-name NAME     Target cluster name (required)
  --namespace NS          Target namespace (default: otel-demo)
  --chart-version VER     Helm chart version (default: 0.31.0)
  --disable-jaeger        Disable Jaeger tracing
  --disable-prometheus    Disable Prometheus metrics
  --dry-run               Show what would be done without executing
EOF
    echo ""
    cat << 'EOF'
EXAMPLES:
  ./scripts/operations/deploy_otel.sh --cluster-name my-workshop
  ./scripts/operations/deploy_otel.sh --cluster-name test-cluster --namespace demo --disable-jaeger
  ./scripts/operations/deploy_otel.sh --cluster-name prod --chart-version 0.30.0

PREREQUISITES:
  - kubectl configured for target cluster
  - helm installed
  - Cluster must have AWS Load Balancer Controller
EOF
    help_footer
}

# Function to set LOCUST_HOST to the preferred FQDN (fallback to ALB hostname)
set_locust_host() {
    log_info "Configuring LOCUST_HOST for load-generator..."
    
    local fqdn
    fqdn=$(get_frontend_fqdn)
    if [ -z "$fqdn" ]; then
        log_warning "Could not determine frontend hostname; skipping LOCUST_HOST configuration"
        return 0
    fi
    local target_url="http://$fqdn"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would set LOCUST_HOST to $target_url"
        return 0
    fi
    
    # Patch deployment env var safely and wait for rollout
    kubectl -n "$NAMESPACE" set env deploy/opentelemetry-demo-loadgenerator "LOCUST_HOST=$target_url" || {
        log_warning "load-generator deployment not found; skipping LOCUST_HOST configuration"
        return 0
    }
    log_info "Waiting for load-generator rollout..."
    kubectl -n "$NAMESPACE" rollout status deploy/opentelemetry-demo-loadgenerator --timeout=180s || log_warning "load-generator rollout wait timed out"
    
    local current
    current=$(kubectl -n "$NAMESPACE" get deploy opentelemetry-demo-loadgenerator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LOCUST_HOST")].value}' 2>/dev/null || echo "")
    log_success "LOCUST_HOST set to: ${current:-$target_url}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --chart-version)
            HELM_CHART_VERSION="$2"
            shift 2
            ;;
        --disable-jaeger)
            ENABLE_JAEGER=false
            shift
            ;;
        --disable-prometheus)
            ENABLE_PROMETHEUS=false
            shift
            ;;
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$CLUSTER_NAME" ]; then
    log_error "Cluster name is required"
    show_help
    exit 1
fi

# Function to deploy OpenTelemetry demo
deploy_otel_demo() {
    log_section "Deploying OpenTelemetry Demo"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would deploy OpenTelemetry demo"
        return 0
    fi
    
    # Ensure namespace exists
    ensure_namespace "$NAMESPACE"
    
    # Add OpenTelemetry Helm repository
    ensure_helm_repo "open-telemetry" "https://open-telemetry.github.io/opentelemetry-helm-charts"
    
    # Prepare Helm values
    local values_file="/tmp/otel-demo-values.yaml"
    cat > "$values_file" << EOF
default:
  env:
    - name: OTEL_SERVICE_NAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: "metadata.labels['app.kubernetes.io/component']"
    - name: OTEL_K8S_NAMESPACE
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.namespace
    - name: OTEL_K8S_NODE_NAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: spec.nodeName
    - name: OTEL_K8S_POD_NAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.name
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://opentelemetry-demo-otelcol:4317"
    - name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
      value: "http://opentelemetry-demo-otelcol:4318/v1/traces"
    - name: OTEL_COLLECTOR_HOST
      value: "opentelemetry-demo-otelcol"
    - name: OTEL_COLLECTOR_NAME
      value: "opentelemetry-demo-otelcol"

jaeger:
  enabled: $ENABLE_JAEGER
prometheus:
  enabled: false
grafana:
  enabled: false

# Disable heavy OpenSearch subchart to speed up demo startup
opensearch:
  enabled: false

opentelemetry-collector:
  enabled: true
  mode: deployment
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      prometheus:
        config:
          scrape_configs:
            - job_name: 'otel-collector'
              scrape_interval: 10s
              static_configs:
                - targets: ['0.0.0.0:8888']
    processors:
      batch: {}
      memory_limiter:
        check_interval: 5s
        limit_mib: 400
        spike_limit_mib: 200
    exporters:
      otlp:
        endpoint: opentelemetry-demo-jaeger-collector:4317
        tls:
          insecure: true
      logging:
        loglevel: debug
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp, logging]
        metrics:
          receivers: [otlp, prometheus]
          processors: [memory_limiter, batch]
          exporters: [logging]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [logging]
EOF
    
    # Install OpenTelemetry demo
    log_info "Installing OpenTelemetry demo application..."
    helm upgrade --install opentelemetry-demo open-telemetry/opentelemetry-demo \
        --namespace "$NAMESPACE" \
        --version "$HELM_CHART_VERSION" \
        --values "$values_file" \
        --wait \
        --timeout 10m
    
    # Cleanup temporary file
    rm -f "$values_file"
    
    log_success "OpenTelemetry demo deployed successfully"
}

## Consolidated ingress is applied by workshop.sh; no per-app ingress here

# Function to wait for deployment
wait_for_deployment() {
    log_info "Waiting for OpenTelemetry demo to be ready..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would wait for deployment"
        return 0
    fi
    
    # Wait for main components to be ready
    local components=(
        "opentelemetry-demo-frontend"
        "opentelemetry-demo-adservice"
        "opentelemetry-demo-cartservice"
        "opentelemetry-demo-checkoutservice"
        "opentelemetry-demo-currencyservice"
        "opentelemetry-demo-emailservice"
        "opentelemetry-demo-paymentservice"
        "opentelemetry-demo-productcatalogservice"
        "opentelemetry-demo-recommendationservice"
        "opentelemetry-demo-shippingservice"
    )
    
    for component in "${components[@]}"; do
        kubectl wait --for=condition=available --timeout=300s deployment/"$component" -n "$NAMESPACE" || {
            log_warning "Timeout waiting for $component, but continuing..."
        }
    done
    
    log_success "OpenTelemetry demo is ready"
}

# Function to display endpoints
display_endpoints() {
    log_section "OpenTelemetry Demo Endpoints"
    
    # Use consolidated ingress hostname
    local frontend_alb=$(kubectl get ingress -n "$NAMESPACE" consolidated-demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
    
    echo -e "${GREEN}🌐 Application Endpoints:${NC}"
    echo "  Frontend:    http://$frontend_alb"
    echo ""
    
    # In consolidated mode, Jaeger (if enabled) is expected to be path-routed via the consolidated ingress
    
    echo -e "${YELLOW}📋 Port Forward Commands:${NC}"
    echo "  Jaeger:      kubectl port-forward -n $NAMESPACE svc/opentelemetry-demo-jaeger-query 16686:16686"
    echo "  Prometheus:  kubectl port-forward -n $NAMESPACE svc/opentelemetry-demo-prometheus-server 9090:80"
    echo "  Grafana:     kubectl port-forward -n $NAMESPACE svc/opentelemetry-demo-grafana 3000:80"
    echo ""
}

# Main execution
main() {
    print_banner
    
    log_info "Deploying OpenTelemetry demo with configuration:"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  Namespace: $NAMESPACE"
    echo "  Chart Version: $HELM_CHART_VERSION"
    echo "  Jaeger Enabled: $ENABLE_JAEGER"
    echo "  Prometheus Enabled: $ENABLE_PROMETHEUS"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    
    # Update kubeconfig
    update_kubeconfig "$CLUSTER_NAME" "$AWS_REGION"
    
    # Deploy components
    deploy_otel_demo
    wait_for_deployment
    set_locust_host
    
    # Display information
    display_endpoints
    
    log_success "OpenTelemetry demo deployment completed!"
    log_info "The application may take a few more minutes to be fully accessible via ALB"
}

# Run main function
main "$@"
