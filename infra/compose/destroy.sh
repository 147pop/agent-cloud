#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"

if [ "${1:-}" != "--yes" ]; then
  printf '%s\n' 'refusing to remove named volumes; rerun with --yes for destructive cleanup' >&2
  exit 2
fi
if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "missing $ENV_FILE" >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f "$REPOSITORY_ROOT/compose.yaml" down --volumes --remove-orphans
