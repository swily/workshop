#!/bin/bash -e

# Function to convert deployment name to desired service name format
get_service_name() {
  local deployment=$1
  
  # Remove the otel-demo- prefix
  local service_name=${deployment#otel-demo-}
  
  # Convert camelCase to snake_case
  service_name=$(echo $service_name | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\L\2/g')
  
  # Add _service suffix if it doesn't already end with 'service'
  if [[ ! $service_name =~ .*service$ ]]; then
    service_name="${service_name}_service"
  fi
  
  echo $service_name
}

# Get all deployments in the otel-demo namespace
DEPLOYMENTS=$(kubectl get deployment -n otel-demo -o jsonpath='{.items[*].metadata.name}')

# Update each deployment's Gremlin service annotation
for deployment in $DEPLOYMENTS; do
  # Skip non-service deployments
  if [[ $deployment != otel-demo-*service && $deployment != otel-demo-frontend ]]; then
    continue
  fi
  
  # Get the desired service name
  service_name=$(get_service_name $deployment)
  
  echo "Updating $deployment with service name: $service_name"
  kubectl annotate deployment $deployment -n otel-demo "gremlin.com/service-id=$service_name" --overwrite
done

echo "✅ Service names updated successfully!"
echo "The next time Gremlin refreshes its service catalog, you should see the new service names."
