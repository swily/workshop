#!/bin/bash

# Gremlin Service Discovery Annotations
# Applies Gremlin annotations to services and deployments for automatic service discovery

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"

source "$LIB_DIR/common.sh"
source "$LIB_DIR/gremlin.sh"

service_count=0
deployment_count=0

# Function to determine service category based on name
get_service_category() {
    local service_name="$1"
    
    if [[ "$service_name" == *"frontend"* ]]; then
        echo "frontend"
    elif [[ "$service_name" == *"cart"* ]]; then
        echo "shopping"
    elif [[ "$service_name" == *"product"* ]]; then
        echo "catalog"
    elif [[ "$service_name" == *"payment"* ]]; then
        echo "payment"
    elif [[ "$service_name" == *"shipping"* ]]; then
        echo "fulfillment"
    elif [[ "$service_name" == *"currency"* ]]; then
        echo "payment"
    elif [[ "$service_name" == *"checkout"* ]]; then
        echo "checkout"
    elif [[ "$service_name" == *"email"* ]]; then
        echo "notification"
    elif [[ "$service_name" == *"recommendation"* ]]; then
        echo "recommendation"
    elif [[ "$service_name" == *"ad"* ]]; then
        echo "marketing"
    elif [[ "$service_name" == *"otelcol"* || "$service_name" == *"jaeger"* || "$service_name" == *"prometheus"* || "$service_name" == *"grafana"* ]]; then
        echo "observability"
    elif [[ "$service_name" == *"kafka"* ]]; then
        echo "messaging"
    elif [[ "$service_name" == *"valkey"* || "$service_name" == *"redis"* ]]; then
        echo "database"
    else
        echo "other"
    fi
}

ensure_standard_k8s_pod_labels() {
    local namespace="$1"
    local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    [[ -z "$deployments" ]] && return 0

    for deployment in $deployments; do
        local base_name="${deployment#opentelemetry-demo-}"
        local component=$(get_service_category "$deployment")
        local instance=$(kubectl get deploy "$deployment" -n "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null || echo "opentelemetry-demo")

        kubectl patch deployment "$deployment" -n "$namespace" --type merge --patch '{
          "spec": {
            "template": {
              "metadata": {
                "labels": {
                  "app.kubernetes.io/name": "'"$base_name"'",
                  "app.kubernetes.io/component": "'"$component"'",
                  "app.kubernetes.io/instance": "'"$instance"'"
                }
              }
            }
          }
        }' >/dev/null 2>&1 || true
    done
}

annotate_services() {
    local namespace="$1"
    local team_id="${2:-}"
    local services=$(kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    [[ -z "$services" ]] && return 0

    for service in $services; do
        local category=$(get_service_category "$service")
        kubectl annotate service "$service" -n "$namespace" \
            "gremlin.com/service-id=$service" \
            "gremlin.com/service-type=kubernetes" \
            "gremlin.com/tags=environment:demo,app:otel-demo,category:${category}" \
            "gremlin.com/description=OpenTelemetry Demo ${service} service" \
            --overwrite >/dev/null 2>&1 || true
        
        [[ -n "$team_id" ]] && kubectl annotate service "$service" -n "$namespace" "gremlin.com/team-id=$team_id" --overwrite >/dev/null 2>&1 || true
        service_count=$((service_count + 1))
    done
}

annotate_deployments() {
    local namespace="$1"
    local team_id="${2:-}"
    local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    [[ -z "$deployments" ]] && return 0

    for deployment in $deployments; do
        local category=$(get_service_category "$deployment")
        
        kubectl annotate deployment "$deployment" -n "$namespace" \
            "gremlin.com/service-id=$deployment" \
            "gremlin.com/service-type=kubernetes" \
            "gremlin.com/tags=environment:demo,app:otel-demo,category:${category}" \
            "gremlin.com/description=OpenTelemetry Demo ${deployment} deployment" \
            --overwrite >/dev/null 2>&1 || true
        
        [[ -n "$team_id" ]] && kubectl annotate deployment "$deployment" -n "$namespace" "gremlin.com/team-id=$team_id" --overwrite >/dev/null 2>&1 || true
        
        kubectl patch deployment "$deployment" -n "$namespace" --type=json -p='[
          {"op":"add","path":"/spec/template/metadata/annotations","value":{}},
          {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1service-id","value":"'${deployment}'"},
          {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1service-type","value":"kubernetes"},
          {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1tags","value":"environment:demo,app:otel-demo,category:'${category}'"},
          {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1description","value":"OpenTelemetry Demo '${deployment}' deployment"}
        ]' >/dev/null 2>&1 || true
        
        [[ -n "$team_id" ]] && kubectl patch deployment "$deployment" -n "$namespace" --type=json -p='[
          {"op":"add","path":"/spec/template/metadata/annotations/gremlin.com~1team-id","value":"'${team_id}'"}
        ]' >/dev/null 2>&1 || true
        
        deployment_count=$((deployment_count + 1))
    done
}

configure_gremlin_agent() {
    is_dry_run && return 0
    kubectl get daemonset gremlin -n gremlin >/dev/null 2>&1 || return 0
    
    kubectl patch daemonset gremlin -n gremlin --patch 'spec:
  template:
    spec:
      containers:
      - name: gremlin
        env:
        - name: GREMLIN_CONTAINER_LABELS
          value: "app.kubernetes.io/component,app.kubernetes.io/name,app.kubernetes.io/instance"
        - name: GREMLIN_CLIENT_TAGS
          value: "app.kubernetes.io/component,app.kubernetes.io/name,app.kubernetes.io/instance"
        - name: GREMLIN_COLLECT_DNS
          value: "true"
        - name: GREMLIN_COLLECT_PODS
          value: "true"' >/dev/null 2>&1 && kubectl rollout restart daemonset/gremlin -n gremlin >/dev/null 2>&1
}

restart_deployments() {
    local namespace="$1"
    is_dry_run && return 0
    local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    [[ -n "$deployments" ]] && for deployment in $deployments; do kubectl rollout restart deployment/"$deployment" -n "$namespace" >/dev/null 2>&1 || true; done
}

show_sample_annotations() {
    local namespace="$1"
    local sample_service=$(kubectl get services -n "$namespace" -o jsonpath='{.items[?(@.metadata.name=="opentelemetry-demo-frontendproxy")].metadata.name}' 2>/dev/null || 
        kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -i frontend | head -1)
    
    if [[ -n "$sample_service" ]]; then
        echo "Sample: $sample_service"
        kubectl get service "$sample_service" -n "$namespace" -o jsonpath='{.metadata.annotations}' 2>/dev/null | 
            jq -r 'to_entries[] | select(.key | startswith("gremlin.com/")) | "  \(.key): \(.value)"' 2>/dev/null || true
    fi
}

# Usage function
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [NAMESPACE]

Consolidated Gremlin annotations script - applies all necessary Gremlin service discovery annotations.

ARGUMENTS:
  NAMESPACE           Target namespace (default: otel-demo)

OPTIONS:
  -t, --team-id ID    Gremlin team ID to add to annotations
  -n, --dry-run       Show what would be done without making changes
  -h, --help          Show this help message

EXAMPLES:
  # Annotate otel-demo namespace
  $0

  # Annotate specific namespace with team ID
  $0 -t team-abc123 my-namespace

  # Dry run to see what would be done
  $0 --dry-run

EOF
}

# Parse command line arguments
parse_arguments() {
    local namespace="otel-demo"
    local team_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--team-id)
                team_id="$2"
                shift 2
                ;;
            -n|--dry-run)
                export DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                namespace="$1"
                shift
                ;;
        esac
    done
    
    echo "$namespace $team_id"
}

main() {
    log_section "Gremlin Service Discovery Setup"
    
    local args=$(parse_arguments "$@")
    local namespace=$(echo "$args" | cut -d' ' -f1)
    local team_id=$(echo "$args" | cut -d' ' -f2)
    
    echo "Namespace: $namespace"
    [[ -n "$team_id" ]] && echo "Team ID: $team_id"
    is_dry_run && echo "Mode: DRY RUN"
    echo ""
    
    kubectl get namespace "$namespace" >/dev/null 2>&1 || { log_error "Namespace '$namespace' does not exist"; exit 1; }
    
    create_gremlin_rbac
    annotate_services "$namespace" "$team_id"
    annotate_deployments "$namespace" "$team_id"
    configure_gremlin_agent
    ensure_standard_k8s_pod_labels "$namespace"
    restart_deployments "$namespace"
    verify_gremlin_access >/dev/null 2>&1
    
    echo ""
    show_sample_annotations "$namespace"
    echo ""
    echo "Complete: $service_count services, $deployment_count deployments annotated"
    echo "Note: Services appear in Gremlin UI within 2-5 minutes"
    echo "Check: https://app.gremlin.com/reliability/status-checks"
}

# Execute main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
