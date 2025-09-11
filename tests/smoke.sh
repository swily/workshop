#!/bin/bash
set -Eeuo pipefail

# Simple dry-run smoke to validate orchestrator wiring without mutating infra.
# Usage: tests/smoke.sh [--cluster-name NAME] [--region REGION]

CLUSTER_NAME="${1:-smoke-demo}"
REGION="${2:-us-east-2}"

export DRY_RUN=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

printf "\n==> Smoke: build_new (dry run)\n"
./workshop.sh --action build_new --cluster-name "$CLUSTER_NAME" --region "$REGION" || exit 1

printf "\n==> Smoke: deploy_existing (dry run)\n"
./workshop.sh --action deploy_existing --cluster-name "$CLUSTER_NAME" --region "$REGION" || exit 1

printf "\n==> Smoke: gremlin_only (dry run)\n"
./workshop.sh --action gremlin_only --cluster-name "$CLUSTER_NAME" --region "$REGION" || exit 1

printf "\n==> Smoke: cluster_cleanup (dry run)\n"
./scripts/operations/cluster_cleanup.sh --cluster-name "$CLUSTER_NAME" --region "$REGION" --dry-run || exit 1

printf "\n✅ Smoke tests (dry run) completed\n"
