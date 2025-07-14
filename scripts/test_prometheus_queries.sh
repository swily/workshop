#!/bin/bash

# Test script to verify Prometheus queries

# Prometheus instances configuration
INSTANCES=("monitoring" "otel-demo" "istio-system")
URLS=("localhost:9090" "localhost:9091" "localhost:9092")
QUERIES=("up" "up" "up")

# Get the index of an instance name
get_index() {
    local instance="$1"
    for i in "${!INSTANCES[@]}"; do
        if [[ "${INSTANCES[$i]}" = "$instance" ]]; then
            echo $i
            return 0
        fi
    done
    echo -1
    return 1
}

# Test each Prometheus instance
for i in "${!INSTANCES[@]}"; do
    instance="${INSTANCES[$i]}"
    url="${URLS[$i]}"
    query="${QUERIES[$i]}"
    
    echo -e "\n=== Testing $instance Prometheus (${url}) ==="
    
    # Test basic connectivity
    echo "Testing connectivity to ${url}..."
    if ! curl -s --connect-timeout 5 "http://${url}/-/healthy" >/dev/null; then
        echo "❌ Failed to connect to ${instance} Prometheus at ${url}"
        continue
    fi
    echo "✅ Connected to ${instance} Prometheus"
    
    # Test sample query
    echo -e "\nRunning test query: ${query}"
    response=$(curl -s --connect-timeout 5 "http://${url}/api/v1/query?query=${query}")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo "❌ Query failed"
        continue
    fi
    
    # Check if response is valid JSON
    if ! jq -e . >/dev/null 2>&1 <<<"$response"; then
        echo "❌ Invalid JSON response"
        echo "Response: $response"
        continue
    fi
    
    # Check if we got results
    result_count=$(jq -r '.data.result | length' <<<"$response" 2>/dev/null)
    if [ -z "$result_count" ] || [ "$result_count" -eq 0 ]; then
        echo "⚠️  No results returned"
    else
        echo "✅ Success! Found ${result_count} results"
    fi
    
    # Show a sample of the results
    echo -e "\nSample results:"
    jq -r '.data.result[0:2]' <<<"$response"
done

echo -e "\n=== Test complete ==="
