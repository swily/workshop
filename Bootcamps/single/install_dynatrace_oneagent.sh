#!/bin/bash

TEAM_NUMBER=$1

DYNATRACE_API_TOKEN=$(aws ssm get-parameter --name '/Bootcamp/DynatraceAPIToken' --with-decryption | jq -r '.Parameter.Value')
DYNATRACE_INGEST_TOKEN=$(aws ssm get-parameter --name '/Bootcamp/DynatraceIngestToken' --with-decryption | jq -r '.Parameter.Value')

helm get values dynatrace-operator -n dynatrace > /dev/null || \
helm install dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --create-namespace \
  --namespace dynatrace \
  --atomic || exit 0
sleep 120
kubectl apply -f <(sed -e "s/{{.TEAM_NUMBER}}/${TEAM_NUMBER}/" -e "s/{{.DYNATRACE_API_TOKEN}}/${DYNATRACE_API_TOKEN}/" -e "s/{{.DYNATRACE_INGEST_TOKEN}}/${DYNATRACE_INGEST_TOKEN}/" ./templates/dynakube.yaml)