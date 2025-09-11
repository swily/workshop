#!/bin/bash
#
# Monitoring platform orchestration for workshop scripts
# Handles setup and configuration of various monitoring platforms
#

# Source common functions if not already loaded
if [[ -z "$RED" ]]; then
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$LIB_DIR/common.sh"
fi

# Function to setup comprehensive monitoring
setup_comprehensive_monitoring() {
    local platform="$1"
    
    log_section "Setting up Comprehensive Monitoring: $platform"
    
    # If a base domain is provided, ensure ExternalDNS is installed for DNS automation
    if [[ -n "${BASE_DOMAIN:-}" ]]; then
        setup_externaldns
    fi

    case "$platform" in
        "grafana"|"prometheus")
            setup_grafana_monitoring
            ;;
        "dynatrace")
            setup_dynatrace_monitoring
            ;;
        "newrelic")
            setup_newrelic_monitoring
            ;;
        "datadog")
            setup_datadog_monitoring
            ;;
        "appdynamics")
            setup_appdynamics_monitoring
            ;;
        "none")
            log_info "Skipping monitoring setup as requested"
            return 0
            ;;
        *)
            log_warning "Unknown monitoring platform: $platform, defaulting to Grafana"
            setup_grafana_monitoring
            ;;
    esac
    
    # Setup common monitoring components
    setup_service_monitors
    setup_recording_rules
    
    log_success "Comprehensive monitoring setup completed"
}

# Provision a Grafana datasource pointing to Jaeger in the otel-demo namespace
ensure_grafana_jaeger_datasource() {
    log_info "Ensuring Grafana Jaeger datasource is configured..."

    if is_dry_run; then
        log_warning "[DRY RUN] Would create Grafana Jaeger datasource ConfigMap in monitoring namespace"
        return 0
    fi

    # Jaeger Query service URL within the cluster
    local jaeger_url="http://opentelemetry-demo-jaeger-query.otel-demo.svc.cluster.local:16686"

    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-jaeger
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  jaeger-datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: Jaeger
        type: jaeger
        access: proxy
        url: ${jaeger_url}
        isDefault: false
        editable: true
EOF

    log_success "Grafana Jaeger datasource configured"
}

# Function to setup Prometheus ingress
setup_prometheus_ingress() {
    log_info "Setting up Prometheus ingress..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup Prometheus ingress"
        return 0
    fi
    
    PROM_HOSTNAME="${HOST_PREFIX:-}${PROMETHEUS_HOSTNAME_SUFFIX:-prometheus}.${BASE_DOMAIN:-}"
    LISTEN_PORTS='[{"HTTP":80}]'
    TLS_ANNOTS=""
    if [[ "${HTTPS_MODE:-off}" == "alb-acm" && -n "${ACM_CERT_ARN:-}" ]]; then
        LISTEN_PORTS='[{"HTTP":80,"HTTPS":443}]'
        TLS_ANNOTS="    alb.ingress.kubernetes.io/ssl-redirect: '443'\n    alb.ingress.kubernetes.io/certificate-arn: ${ACM_CERT_ARN}"
    fi

    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '${LISTEN_PORTS}'
    external-dns.alpha.kubernetes.io/hostname: "${PROM_HOSTNAME}"
${TLS_ANNOTS}
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-prometheus
            port:
              number: 9090
EOF
    
    log_success "Prometheus ingress configured"
}

# Install ExternalDNS for Route53 automation (idempotent)
setup_externaldns() {
    log_info "Ensuring ExternalDNS is installed for domain: ${BASE_DOMAIN}"

    if is_dry_run; then
        log_warning "[DRY RUN] Would install/configure ExternalDNS"
        return 0
    fi

    # Ensure Helm repo
    ensure_helm_repo "bitnami" "https://charts.bitnami.com/bitnami"

    # Optionally use IRSA role if provided via EXTERNALDNS_IAM_ROLE_ARN
    local sa_annotations=""
    if [[ -n "${EXTERNALDNS_IAM_ROLE_ARN:-}" ]]; then
        sa_annotations="--set serviceAccount.annotations.\"eks.amazonaws.com/role-arn\"=${EXTERNALDNS_IAM_ROLE_ARN}"
    fi

    # Install/upgrade ExternalDNS
    helm upgrade --install external-dns bitnami/external-dns \
        --namespace kube-system \
        --set provider=aws \
        --set policy=upsert-only \
        --set txtOwnerId="workshop-${CLUSTER_NAME}" \
        --set domainFilters[0]="${BASE_DOMAIN}" \
        --set serviceAccount.create=true \
        ${sa_annotations}

    log_success "ExternalDNS is configured"
}

# Function to setup Grafana + Prometheus monitoring
setup_grafana_monitoring() {
    log_info "Setting up Grafana + Prometheus monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup Grafana monitoring"
        return 0
    fi
    
    # Ensure Prometheus Operator is installed (should be done in cluster setup)
    if ! kubectl get deployment -n monitoring kube-prometheus-stack-operator &>/dev/null; then
        log_info "Installing Prometheus Operator..."
        ensure_helm_repo "prometheus-community" "https://prometheus-community.github.io/helm-charts"
        
        helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
            --set grafana.adminPassword=admin123
    fi
    
    # Install OpenTelemetry monitoring dashboards
    install_otel_dashboards
    # Ensure Jaeger datasource is available in central Grafana
    ensure_grafana_jaeger_datasource
    
    # Setup Grafana ingress
    setup_grafana_ingress
    # Setup Prometheus ingress
    setup_prometheus_ingress

    log_success "Grafana monitoring setup completed"
}

# Function to setup Dynatrace monitoring
setup_dynatrace_monitoring() {
    log_info "Setting up Dynatrace monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup Dynatrace monitoring"
        return 0
    fi
    
    if [ -z "$DYNATRACE_API_TOKEN" ] || [ -z "$DYNATRACE_INSTANCE_ID" ]; then
        log_error "Dynatrace credentials not provided"
        return 1
    fi
    
    # Add Dynatrace Helm repository
    ensure_helm_repo "dynatrace" "https://raw.githubusercontent.com/Dynatrace/helm-charts/master/repos/stable"
    
    # Install Dynatrace Operator
    helm upgrade --install dynatrace-operator dynatrace/dynatrace-operator \
        --namespace dynatrace \
        --create-namespace \
        --set installCRD=true
    
    # Create DynaKube custom resource
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: dynakube
  namespace: dynatrace
type: Opaque
data:
  apiToken: $(echo -n "$DYNATRACE_API_TOKEN" | base64)
  dataIngestToken: $(echo -n "$DYNATRACE_API_TOKEN" | base64)
---
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynakube
  namespace: dynatrace
spec:
  apiUrl: https://$DYNATRACE_INSTANCE_ID.dynatrace.com/api
  oneAgent:
    cloudNativeFullStack:
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
        operator: Exists
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
        limits:
          cpu: 300m
          memory: 1.5Gi
  activeGate:
    capabilities:
    - routing
    - kubernetes-monitoring
    - dynatrace-api
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1.5Gi
EOF
    
    wait_for_pods "dynatrace" "app.kubernetes.io/name=dynatrace-operator"
    
    log_success "Dynatrace monitoring setup completed"
}

# Function to setup New Relic monitoring
setup_newrelic_monitoring() {
    log_info "Setting up New Relic monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup New Relic monitoring"
        return 0
    fi
    
    if [ -z "$NEWRELIC_API_KEY" ]; then
        log_error "New Relic API key not provided"
        return 1
    fi
    
    # Add New Relic Helm repository
    ensure_helm_repo "newrelic" "https://helm-charts.newrelic.com"
    
    # Install New Relic Bundle
    helm upgrade --install newrelic-bundle newrelic/nri-bundle \
        --namespace newrelic \
        --create-namespace \
        --set global.licenseKey="$NEWRELIC_API_KEY" \
        --set global.cluster="$CLUSTER_NAME" \
        --set infrastructure.enabled=true \
        --set prometheus.enabled=true \
        --set webhook.enabled=true \
        --set ksm.enabled=true \
        --set kubeEvents.enabled=true \
        --set logging.enabled=true
    
    wait_for_pods "newrelic" "app.kubernetes.io/name=nri-bundle"
    
    log_success "New Relic monitoring setup completed"
}

# Function to setup DataDog monitoring
setup_datadog_monitoring() {
    log_info "Setting up DataDog monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup DataDog monitoring"
        return 0
    fi
    
    if [ -z "$DATADOG_API_KEY" ]; then
        log_error "DataDog API key not provided"
        return 1
    fi
    
    # Add DataDog Helm repository
    ensure_helm_repo "datadog" "https://helm.datadoghq.com"
    
    # Install DataDog Agent
    helm upgrade --install datadog-agent datadog/datadog \
        --namespace datadog \
        --create-namespace \
        --set datadog.apiKey="$DATADOG_API_KEY" \
        --set datadog.appKey="$DATADOG_APP_KEY" \
        --set datadog.site="datadoghq.com" \
        --set datadog.logs.enabled=true \
        --set datadog.logs.containerCollectAll=true \
        --set datadog.apm.enabled=true \
        --set datadog.processAgent.enabled=true \
        --set datadog.systemProbe.enabled=true \
        --set clusterAgent.enabled=true \
        --set clusterAgent.metricsProvider.enabled=true
    
    wait_for_pods "datadog" "app=datadog-agent"
    
    log_success "DataDog monitoring setup completed"
}

# Function to setup AppDynamics monitoring
setup_appdynamics_monitoring() {
    log_info "Setting up AppDynamics monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup AppDynamics monitoring"
        return 0
    fi
    
    if [ -z "$APPDYNAMICS_CONTROLLER_HOST" ] || [ -z "$APPDYNAMICS_ACCOUNT_NAME" ]; then
        log_error "AppDynamics credentials not provided"
        return 1
    fi
    
    # Create AppDynamics namespace
    ensure_namespace "appdynamics"
    
    # Create secret for AppDynamics credentials
    kubectl create secret generic cluster-agent-secret \
        --namespace appdynamics \
        --from-literal=controller-key="$APPDYNAMICS_API_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install AppDynamics Cluster Agent
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: appdynamics-cluster-agent
  namespace: appdynamics
spec:
  replicas: 1
  selector:
    matchLabels:
      name: appdynamics-cluster-agent
  template:
    metadata:
      labels:
        name: appdynamics-cluster-agent
    spec:
      serviceAccountName: appdynamics-cluster-agent
      containers:
      - name: cluster-agent
        image: appdynamics/cluster-agent:latest
        env:
        - name: APPDYNAMICS_CONTROLLER_HOST_NAME
          value: "$APPDYNAMICS_CONTROLLER_HOST"
        - name: APPDYNAMICS_CONTROLLER_PORT
          value: "443"
        - name: APPDYNAMICS_CONTROLLER_SSL_ENABLED
          value: "true"
        - name: APPDYNAMICS_AGENT_ACCOUNT_NAME
          value: "$APPDYNAMICS_ACCOUNT_NAME"
        - name: APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: cluster-agent-secret
              key: controller-key
        - name: APPDYNAMICS_CLUSTER_NAME
          value: "$CLUSTER_NAME"
        resources:
          limits:
            cpu: 200m
            memory: 300Mi
          requests:
            cpu: 100m
            memory: 200Mi
EOF
    
    wait_for_pods "appdynamics" "name=appdynamics-cluster-agent"
    
    log_success "AppDynamics monitoring setup completed"
}

# Function to install OpenTelemetry dashboards
install_otel_dashboards() {
    log_info "Installing OpenTelemetry dashboards..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would install OpenTelemetry dashboards"
        return 0
    fi
    
    # Create ConfigMap with dashboard definitions
    kubectl create configmap otel-dashboards \
        --namespace monitoring \
        --from-file="$SCRIPT_DIR/monitoring/grafana/dashboards/" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Label the ConfigMap so Grafana picks it up
    kubectl label configmap otel-dashboards \
        --namespace monitoring \
        grafana_dashboard=1 \
        --overwrite
    
    log_success "OpenTelemetry dashboards installed"
}

# Function to setup Grafana ingress
setup_grafana_ingress() {
    log_info "Setting up Grafana ingress..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup Grafana ingress"
        return 0
    fi
    
    # Build common annotations
    GRAFANA_HOSTNAME="${HOST_PREFIX:-}${GRAFANA_HOSTNAME_SUFFIX:-grafana}.${BASE_DOMAIN:-}"
    LISTEN_PORTS='[{"HTTP":80}]'
    TLS_ANNOTS=""
    if [[ "${HTTPS_MODE:-off}" == "alb-acm" && -n "${ACM_CERT_ARN:-}" ]]; then
        LISTEN_PORTS='[{"HTTP":80,"HTTPS":443}]'
        TLS_ANNOTS="    alb.ingress.kubernetes.io/ssl-redirect: '443'\n    alb.ingress.kubernetes.io/certificate-arn: ${ACM_CERT_ARN}"
    fi

    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '${LISTEN_PORTS}'
    external-dns.alpha.kubernetes.io/hostname: "${GRAFANA_HOSTNAME}"
${TLS_ANNOTS}
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
EOF
    
    log_success "Grafana ingress configured"
}

# Function to setup service monitors
setup_service_monitors() {
    log_info "Setting up service monitors..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup service monitors"
        return 0
    fi
    
    # Apply service monitors from config directory
    if [ -d "$SCRIPT_DIR/../monitoring/config" ]; then
        kubectl apply -f "$SCRIPT_DIR/../monitoring/config/service-monitors.yaml" 2>/dev/null || log_info "Service monitors config not found"
    fi
    
    log_success "Service monitors configured"
}

# Function to setup recording rules
setup_recording_rules() {
    log_info "Setting up Prometheus recording rules..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup recording rules"
        return 0
    fi
    
    # Apply recording rules from config directory
    if [ -d "$SCRIPT_DIR/../config/gremlin" ]; then
        kubectl apply -f "$SCRIPT_DIR/../config/gremlin/gremlin-*-recording-rules.yaml" 2>/dev/null || log_info "Recording rules not found"
    fi
    
    log_success "Recording rules configured"
}

# Function to setup Gremlin-specific monitoring
setup_gremlin_monitoring() {
    log_info "Setting up Gremlin-specific monitoring..."
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would setup Gremlin monitoring"
        return 0
    fi
    
    # Install Gremlin PNI for health checks
    "$SCRIPT_DIR/../scripts/gremlin_install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --type pni \
        --team-id "$GREMLIN_TEAM_ID" \
        --team-secret "$GREMLIN_TEAM_SECRET"
    
    # Wait for DNS resolution and offer health check creation
    if [ -f "$SCRIPT_DIR/../monitoring/gremlin/create_health_checks.sh" ]; then
        echo -e "${BLUE}🔍 Waiting for DNS resolution before health check creation...${NC}"
        
        # Wait for ALB hostnames to be available
        local prometheus_alb grafana_alb
        prometheus_alb=$(kubectl get ingress -n monitoring prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        grafana_alb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        local attempts=0
        local max_attempts=12
        while [ $attempts -lt $max_attempts ] && ([ -z "$prometheus_alb" ] || [ -z "$grafana_alb" ]); do
            echo -e "${YELLOW}  Waiting for ALB hostnames... (attempt $((attempts+1))/$max_attempts)${NC}"
            sleep 10
            prometheus_alb=$(kubectl get ingress -n monitoring prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            grafana_alb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            attempts=$((attempts+1))
        done
        
        if [ -n "$prometheus_alb" ] && [ -n "$grafana_alb" ]; then
            echo -e "${GREEN}✅ ALB hostnames resolved:${NC}"
            echo -e "  Prometheus: http://$prometheus_alb/api/v1/alerts"
            echo -e "  Grafana: http://$grafana_alb/api/health"
            echo ""
            
            # Prompt user for health check creation
            echo -e "${BLUE}Would you like to automatically create Gremlin health checks?${NC}"
            echo "1) Yes - Create health checks automatically"
            echo "2) No - Print URLs for manual creation in Gremlin UI"
            echo ""
            read -p "Choose option (1-2): " health_check_choice
            
            case $health_check_choice in
                1)
                    echo -e "${YELLOW}Creating health checks automatically...${NC}"
                    export PROMETHEUS_URL="http://$prometheus_alb/api/v1/alerts"
                    export GRAFANA_URL="http://$grafana_alb/api/health"
                    "$SCRIPT_DIR/../monitoring/gremlin/create_health_checks.sh" --auto-mode
                    ;;
                2|*)
                    echo -e "${BLUE}📋 Manual Health Check Creation URLs:${NC}"
                    echo ""
                    echo -e "${GREEN}Prometheus Health Check:${NC}"
                    echo -e "  Name: prometheus-alerts-$(date +%s)"
                    echo -e "  URL: http://$prometheus_alb/api/v1/alerts"
                    echo -e "  Method: GET"
                    echo -e "  Expected Status: 200"
                    echo -e "  Category: ERRORS"
                    echo ""
                    echo -e "${GREEN}Grafana Health Check:${NC}"
                    echo -e "  Name: grafana-health-$(date +%s)"
                    echo -e "  URL: http://$grafana_alb/api/health"
                    echo -e "  Method: GET"
                    echo -e "  Expected Status: 200"
                    echo -e "  Category: ERRORS"
                    echo ""
                    echo -e "${BLUE}Create these manually in the Gremlin UI${NC}"
                    ;;
            esac
        else
            echo -e "${YELLOW}⚠️  ALB hostnames not available after waiting. Printing fallback URLs:${NC}"
            echo ""
            echo -e "${BLUE}📋 Fallback Health Check URLs (use when ALBs are ready):${NC}"
            echo -e "  Prometheus: kubectl get ingress -n monitoring prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
            echo -e "  Grafana: kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
            echo -e "  Then use: http://HOSTNAME/api/v1/alerts (Prometheus) and http://HOSTNAME/api/health (Grafana)"
        fi
    fi
    
    log_success "Gremlin monitoring setup completed"
}

# Function to get monitoring endpoints
get_monitoring_endpoints() {
    log_section "Monitoring Endpoints"
    
    # Grafana
    local grafana_alb=$(kubectl get ingress -n monitoring grafana-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
    echo -e "${GREEN}Grafana:${NC} http://$grafana_alb"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    
    # Prometheus (ALB via Ingress)
    local prometheus_alb=$(kubectl get ingress -n monitoring prometheus-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
    echo -e "${GREEN}Prometheus:${NC} http://$prometheus_alb"
    echo ""
    
    # Platform-specific endpoints
    case "$MONITORING_PLATFORM" in
        "dynatrace")
            echo -e "${GREEN}Dynatrace:${NC} https://$DYNATRACE_INSTANCE_ID.dynatrace.com"
            ;;
        "newrelic")
            echo -e "${GREEN}New Relic:${NC} https://one.newrelic.com"
            ;;
        "datadog")
            echo -e "${GREEN}DataDog:${NC} https://app.datadoghq.com"
            ;;
        "appdynamics")
            echo -e "${GREEN}AppDynamics:${NC} https://$APPDYNAMICS_CONTROLLER_HOST"
            ;;
    esac
}

# Function to cleanup monitoring
cleanup_monitoring() {
    local platform="$1"
    
    log_section "Cleaning up monitoring: $platform"
    
    if is_dry_run; then
        log_warning "[DRY RUN] Would cleanup monitoring"
        return 0
    fi
    
    case "$platform" in
        "grafana"|"prometheus")
            helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
            ;;
        "dynatrace")
            helm uninstall dynatrace-operator -n dynatrace 2>/dev/null || true
            kubectl delete namespace dynatrace --ignore-not-found=true
            ;;
        "newrelic")
            helm uninstall newrelic-bundle -n newrelic 2>/dev/null || true
            kubectl delete namespace newrelic --ignore-not-found=true
            ;;
        "datadog")
            helm uninstall datadog-agent -n datadog 2>/dev/null || true
            kubectl delete namespace datadog --ignore-not-found=true
            ;;
        "appdynamics")
            kubectl delete namespace appdynamics --ignore-not-found=true
            ;;
        "all")
            cleanup_monitoring "grafana"
            cleanup_monitoring "dynatrace"
            cleanup_monitoring "newrelic"
            cleanup_monitoring "datadog"
            cleanup_monitoring "appdynamics"
            ;;
    esac
    
    log_success "Monitoring cleanup completed"
}
