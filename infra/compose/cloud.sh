#!/usr/bin/env bash
# Runs the cloud CLI inside the cloud-control container: no host Node.js and no
# token export needed. Usage: bash infra/compose/cloud.sh <create|start|stop|status> ...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"

exec docker compose --env-file "$ENV_FILE" -f "$REPOSITORY_ROOT/compose.yaml" \
  exec -T cloud-control node dist/src/cli.js "$@"
