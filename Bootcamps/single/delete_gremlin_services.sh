#!/bin/bash -e

if [ -z "${GREMLIN_TEAM_ID}" ]; then
  echo "GREMLIN_TEAM_ID environment variable must be set"
  exit 1
fi

if [ -z "${GREMLIN_TEAM_SECRET}" ]; then
  echo "GREMLIN_TEAM_SECRET environment variable must be set"
  exit 1
fi

if [ -z "${CLUSTER_NAME}" ]; then
  echo "CLUSTER_NAME environment variable must be set"
  exit 1
fi

echo "Deleting Gremlin services for cluster ${CLUSTER_NAME}"
echo "Team ID: ${GREMLIN_TEAM_ID}"

curl \
  -q \
  -X GET \
  -H "Content-Type: application/json" \
  -H "Authorization: Key ${GREMLIN_TEAM_SECRET}" \
  "https://api.gremlin.com/v1/services?teamId=${GREMLIN_TEAM_ID}" | jq -r '.items[].serviceId' | while read service_id; do
    curl \
      -q \
      -X DELETE \
      -H "Content-Type: application/json" \
      -H "Authorization: Key ${GREMLIN_TEAM_SECRET}" \
      "https://api.gremlin.com/v1/services/${service_id}?teamId=${GREMLIN_TEAM_ID}"
  done