#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "missing $ENV_FILE" >&2
  exit 1
fi

compose=(docker compose --env-file "$ENV_FILE" -f "$REPOSITORY_ROOT/compose.yaml")
"${compose[@]}" stop cloud-control
"${compose[@]}" stop --timeout 120 game-1
"${compose[@]}" stop postgres
printf '%s\n' 'Compose foundation stopped; named volumes were preserved'
