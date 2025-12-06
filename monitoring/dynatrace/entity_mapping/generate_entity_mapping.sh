#!/bin/bash

# Script to generate Dynatrace entity mapping for OpenTelemetry Demo services
# This script queries the Dynatrace API to get entity IDs for Kubernetes services
# and creates a mapping file with service names and their corresponding entity IDs

# Configuration
DYNATRACE_API_TOKEN="${DYNATRACE_API_TOKEN:-dt0c01.V7B54NASPVKNWAOBECWSXXAI.6DHPH7WJGGMYMTA634BK4M2E6XKFRMINIT6TP5VJF4GHZWALOVGCZEMWOPUAHTFJ}"
DYNATRACE_INSTANCE_ID="${DYNATRACE_INSTANCE_ID:-qpm46186}"
DYNATRACE_ENV_URL="https://${DYNATRACE_INSTANCE_ID}.live.dynatrace.com"
CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
OUTPUT_FILE="$(dirname "$0")/entity_mapping.txt"
SERVICES_FILTER="otel-demo"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    exit 1
fi

# Check if Dynatrace API token is provided
if [ "$DYNATRACE_API_TOKEN" = "dt0c01.V7B54NASPVKNWAOBECWSXXAI.6DHPH7WJGGMYMTA634BK4M2E6XKFRMINIT6TP5VJF4GHZWALOVGCZEMWOPUAHTFJ" ]; then
    echo "Warning: Using default API token from the script. You should set your own token with:"
    echo "export DYNATRACE_API_TOKEN=your-token"
    echo ""
    read -p "Do you want to continue with the default token? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. Please set your Dynatrace API token and try again."
        exit 1
    fi
fi

echo "Generating Dynatrace entity mapping for services matching '${SERVICES_FILTER}' in cluster '${CLUSTER_NAME}'..."

# Get all Kubernetes services in the cluster
echo "Querying Dynatrace API for Kubernetes services..."
ENTITIES=$(curl -s -X GET "${DYNATRACE_ENV_URL}/api/v2/entities?entitySelector=type(KUBERNETES_SERVICE),tag(kubernetes.cluster.name:${CLUSTER_NAME})" \
  -H "Authorization: Api-Token ${DYNATRACE_API_TOKEN}" \
  -H "Accept: application/json")

# Check if API call was successful
if [ -z "$ENTITIES" ] || [[ "$ENTITIES" == *"error"* ]]; then
    echo "Error: Failed to retrieve entities from Dynatrace API."
    echo "Response: $ENTITIES"
    exit 1
fi

# Clear the output file
> "$OUTPUT_FILE"

# Extract service names and entity IDs and write to file
echo "Extracting service names and entity IDs..."
ENTITY_COUNT=$(echo "$ENTITIES" | jq -r ".entities | length")
FILTERED_COUNT=0

for ((i=0; i<$ENTITY_COUNT; i++)); do
    DISPLAY_NAME=$(echo "$ENTITIES" | jq -r ".entities[$i].displayName")
    
    # Check if the display name contains our filter string
    if [[ "$DISPLAY_NAME" == *"$SERVICES_FILTER"* ]]; then
        ENTITY_ID=$(echo "$ENTITIES" | jq -r ".entities[$i].entityId")
        echo "$DISPLAY_NAME: $ENTITY_ID" >> "$OUTPUT_FILE"
        FILTERED_COUNT=$((FILTERED_COUNT + 1))
    fi
done

if [ $FILTERED_COUNT -eq 0 ]; then
    echo "Warning: No services matching '$SERVICES_FILTER' were found in cluster '$CLUSTER_NAME'."
    echo "Please check your filter and cluster name."
    exit 1
else
    echo "Successfully generated entity mapping for $FILTERED_COUNT services."
    echo "Mapping saved to: $OUTPUT_FILE"
    
    # Display the content of the mapping file
    echo ""
    echo "Entity Mapping:"
    cat "$OUTPUT_FILE"
fi
