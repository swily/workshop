#!/bin/bash

# HTTPS Detection Library
# Detects if cluster endpoints should use HTTPS based on ingress configuration

# Detect if HTTPS should be used for cluster endpoints
detect_https_scheme() {
    local ingress_namespace="${1:-otel-demo}"
    local ingress_name="${2:-consolidated-demo-ingress}"
    
    # Check for HTTPS_MODE environment variable
    if [[ "${HTTPS_MODE:-off}" == "alb-acm" && -n "${ACM_CERT_ARN:-}" ]]; then
        echo "https"
        return 0
    fi
    
    # Check ingress annotations for SSL/TLS configuration
    local has_ssl=$(kubectl get ingress -n "$ingress_namespace" "$ingress_name" \
        -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/certificate-arn}' 2>/dev/null)
    
    if [ -n "$has_ssl" ]; then
        echo "https"
        return 0
    fi
    
    # Check for TLS configuration in ingress spec
    local has_tls=$(kubectl get ingress -n "$ingress_namespace" "$ingress_name" \
        -o jsonpath='{.spec.tls}' 2>/dev/null)
    
    if [ -n "$has_tls" ] && [ "$has_tls" != "null" ]; then
        echo "https"
        return 0
    fi
    
    # Default to HTTP
    echo "http"
}

# Get scheme for consolidated ALB
get_consolidated_alb_scheme() {
    detect_https_scheme "otel-demo" "consolidated-demo-ingress"
}

# Get scheme for monitoring ingress
get_monitoring_ingress_scheme() {
    detect_https_scheme "monitoring" "grafana-ingress"
}

# Export functions
export -f detect_https_scheme
export -f get_consolidated_alb_scheme
export -f get_monitoring_ingress_scheme
