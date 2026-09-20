#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

for script in "$SCRIPT_DIR"/*.sh; do
  bash -n "$script"
done

node --check "$SCRIPT_DIR/protocol-status.mjs"

docker compose --env-file "$SCRIPT_DIR/config.example.env" -f "$REPOSITORY_ROOT/compose.yaml" config --quiet
printf '%s\n' 'Compose package checks passed'
