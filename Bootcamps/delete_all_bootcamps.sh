#!/bin/bash

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

get_cluster_status () {
  for team_number in $*; do

    if [ ${team_number} -lt 10 ]; then
      padded_team_number="0${team_number}"
    else
      padded_team_number="${team_number}"
    fi

    eksctl get cluster otel-bootcamp-group-${padded_team_number} -o json | jq -r '.[0].Status' 2> /dev/null
    if [ $? -eq 0 ]; then
      return 1
    fi
  done
  return 0

}

delete_gremlin_services () {
  GREMILN_TEAM_NUMBER=$team_number
  GREMLIN_TEAM_ID=$(aws ssm get-parameter --name "/Bootcamp/TeamSecrets" --with-decryption | jq -r --arg team "Group ${team_number}" '.Parameter.Value | fromjson | .[$team].team_id')
  GREMLIN_API_KEY=$(aws ssm get-parameter --name '/Bootcamp/GremlinApiKey' --with-decryption | jq -r '.Parameter.Value')

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

delete_clusters () {
  while [ $# -gt 1 ]; do
    echo "Deleting cluster: $1"
    (eksctl delete cluster --disable-nodegroup-eviction --name $1) &
    team_number=$(echo $1 | sed -e 's/otel-bootcamp-group-//')
    delete_gremlin_services $team_number
    shift
  done

  # Foreground this last one so we wait for it to complete before proceeding to cluster configuration.
  echo "Deleting cluster: $1"
  eksctl delete cluster --disable-nodegroup-eviction --name $1
  team_number=$(echo $1 | sed -e 's/otel-bootcamp-group-//')
  delete_gremlin_services $team_number
}


delete_clusters $(eksctl get clusters | awk '/^otel-bootcamp-group/ {print $1}')



#if [ -n "$delete_clusters" ]; then
#  echo "Deleting clusters: $delete_clusters"
#  echo "Sleep 10 seconds for cancellation..."
#  sleep 10
#
#  for cluster in ${delete_clusters}; do
#    (eksctl delete cluster --disable-nodegroup-eviction --name $cluster) &
#  done
#
#  echo -n "Waiting for all deletions to complete..."
#  count=0
#  while [ $count -lt 3600 ]; do
#    get_cluster_status $*
#    status=$?
#    if [ $status -eq 0 ]; then
#      break
#    fi
#    sleep 60
#    count=$(($count + 60))
#    echo -n " ${count}"
#  done
#fi
#
#echo "All deletions completed."
#
## Delete the Gremlin services
#
## Get Gremlin API key and teams from SSM
#GREMLIN_API_KEY=$(aws ssm get-parameter --name '/Bootcamp/GremlinAPIKey' --with-decryption | jq -r '.Parameter.Value')
#