#!/bin/bash

# Service Discovery Utility Functions
# This file contains reusable functions for discovering services in Kubernetes

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Discover services in a namespace
# Usage: discover_services <namespace> [label_selector]
discover_services() {
    local namespace="$1"
    local label_selector="${2:-}"
    
    if [ -z "$namespace" ]; then
        echo -e "${RED}Error: Namespace not specified${NC}" >&2
        return 1
    fi

    local query="kubectl get svc -n $namespace --no-headers"
    [ -n "$label_selector" ] && query+=" -l $label_selector"
    
    $query -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ports[0].port}{"\n"}{end}' 2>/dev/null
}

# Get endpoints for a service
# Usage: get_service_endpoints <namespace> <service_name>
get_service_endpoints() {
    local namespace="$1"
    local service_name="$2"
    
    if [ -z "$namespace" ] || [ -z "$service_name" ]; then
        echo -e "${RED}Error: Namespace and service name are required${NC}" >&2
        return 1
    fi

    kubectl get endpoints "$service_name" -n "$namespace" -o jsonpath='{"ip": .subsets[0].addresses[0].ip, "port": .subsets[0].ports[0].port}' 2>/dev/null
}

# Get service URL (for cluster-internal access)
# Usage: get_service_url <namespace> <service_name> [port_name]
get_service_url() {
    local namespace="$1"
    local service_name="$2"
    local port_name="${3:-}"
    
    local port_selector=""
    [ -n "$port_name" ] && port_selector=".spec.ports[?(@.name==\"$port_name\")].port"
    
    local port
    port=$(kubectl get svc "$service_name" -n "$namespace" \
        -o jsonpath="{.spec.ports[0].port$port_selector}" 2>/dev/null)
    
    if [ -z "$port" ]; then
        echo -e "${YELLOW}Warning: Could not determine port for service $service_name${NC}" >&2
        return 1
    fi
    
    echo "http://$service_name.$namespace.svc.cluster.local:$port"
}

# Get pods for a service
# Usage: get_service_pods <namespace> <service_name>
get_service_pods() {
    local namespace="$1"
    local service_name="$2"
    
    if [ -z "$namespace" ] || [ -z "$service_name" ]; then
        echo -e "${RED}Error: Namespace and service name are required${NC}" >&2
        return 1
    fi
    
    # Get the selector for the service
    local selector
    selector=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.selector.app}') 
    
    if [ -z "$selector" ]; then
        echo -e "${YELLOW}Warning: No selector found for service $service_name${NC}" >&2
        return 1
    fi
    
    # Get pods matching the selector
    kubectl get pods -n "$namespace" -l "app=$selector" -o jsonpath='{range .items[*]}{.status.podIP}{"\t"}{.status.phase}{"\n"}{end}' 2>/dev/null
}

# Check if a service is ready
# Usage: is_service_ready <namespace> <service_name>
is_service_ready() {
    local namespace="$1"
    local service_name="$2"
    
    local endpoints
    endpoints=$(kubectl get endpoints "$service_name" -n "$namespace" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
    
    if [ -n "$endpoints" ]; then
        return 0  # Service has endpoints
    else
        return 1  # No endpoints found
    fi
}
