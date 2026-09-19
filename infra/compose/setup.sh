#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "missing $ENV_FILE; copy infra/compose/config.example.env to .env and edit it" >&2
  exit 1
fi

eula="$(sed -n 's/^MINECRAFT_EULA=//p' "$ENV_FILE" | tail -n 1)"
if [ "$eula" != "TRUE" ]; then
  printf '%s\n' "MINECRAFT_EULA must be TRUE in $ENV_FILE" >&2
  exit 1
fi

bind="$(sed -n 's/^GAME_BIND_ADDRESS=//p' "$ENV_FILE" | tail -n 1)"
case "$bind" in
  0.0.0.0|::|'[::]')
    printf '%s\n' "GAME_BIND_ADDRESS must be one host address that clients can reach, not $bind" >&2
    exit 1
    ;;
esac

compose=(docker compose --env-file "$ENV_FILE" -f "$REPOSITORY_ROOT/compose.yaml")
"${compose[@]}" config --quiet
"${compose[@]}" up -d postgres
"${compose[@]}" create game-1
"${compose[@]}" up -d cloud-control

printf '%s\n' 'Compose foundation is ready; game-1 exists stopped and is controlled by cloud-control'
