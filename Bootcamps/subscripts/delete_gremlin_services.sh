#!/bin/bash

get_gremlin_auth () {
  if [ $1 -lt 1 ] || [ $1 -gt 20 ]; then
    echo "Invalid team number. Must be between 1 and 20."
    exit 1
  fi

  if [ $1 -lt 10 ]; then
    team_number="0${1}"
  else
    team_number="$1"
  fi

  GREMILN_TEAM_NUMBER=$team_number
  GREMLIN_TEAM_ID=$(aws ssm get-parameter --name "/Bootcamp/TeamSecrets" --with-decryption | jq -r --arg team "Group ${team_number}" '.Parameter.Value | fromjson | .[$team].team_id')
  GREMLIN_API_KEY=$(aws ssm get-parameter --name '/Bootcamp/GremlinApiKey' --with-decryption | jq -r '.Parameter.Value')
}

get_gremlin_services () {

  curl \
    -q \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Key ${GREMLIN_API_KEY}" \
    "https://api.gremlin.com/v1/services?teamId=${GREMLIN_TEAM_ID}" | jq -r '.items[].serviceId' | while read service_id; do
      curl \
        -q \
        -X DELETE \
        -H "Content-Type: application/json" \
        -H "Authorization: Key ${GREMLIN_API_KEY}" \
        "https://api.gremlin.com/v1/services/${service_id}?teamId=${GREMLIN_TEAM_ID}"
    done
}

get_gremlin_auth $1
get_gremlin_services