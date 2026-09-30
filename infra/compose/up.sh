#!/usr/bin/env bash
# One command from a clean clone to a playable Minecraft endpoint. Safe to rerun:
# the fixed create key replays the same server, and a stopped server is started.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"
CLI="$SCRIPT_DIR/cloud.sh"

usage() {
  printf '%s\n' 'usage: bash infra/compose/up.sh [--accept-eula] [--name NAME] [--timeout SECONDS]' >&2
  exit 2
}

ACCEPT_EULA=0
NAME=minecraft
TIMEOUT=300
while [ "$#" -gt 0 ]; do
  case "$1" in
    --accept-eula) ACCEPT_EULA=1 ;;
    --name) [ "$#" -ge 2 ] || usage; NAME="$2"; shift ;;
    --timeout) [ "$#" -ge 2 ] || usage; TIMEOUT="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | tail -n 1; }
random_hex() { head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

if [ ! -f "$ENV_FILE" ]; then
  if [ "$ACCEPT_EULA" != 1 ]; then
    printf '%s\n' 'no .env yet: rerun with --accept-eula to accept the Minecraft EULA (https://aka.ms/MinecraftEULA)' >&2
    exit 1
  fi
  if docker volume ls -q | grep -qx cloud_postgres-data; then
    printf '%s\n' 'a previous installation left its volumes, and new credentials cannot open them;' \
      'restore that .env, or run docker volume rm cloud_postgres-data cloud_game-world (deletes its world)' >&2
    exit 1
  fi
  (
    umask 177
    printf 'CLOUD_MACHINE_TOKEN=%s\nPOSTGRES_PASSWORD=%s\nMINECRAFT_EULA=TRUE\n' \
      "$(random_hex)$(random_hex)" "$(random_hex)" >"$ENV_FILE"
  )
  printf '%s\n' "generated $ENV_FILE with random credentials (not printed)"
fi

bash "$SCRIPT_DIR/setup.sh"

control_ready() {
  local out
  out="$(bash "$CLI" status 00000000-0000-0000-0000-000000000000 2>&1 || true)"
  printf '%s' "$out" | grep -q '"error"' && ! printf '%s' "$out" | grep -q control_unreachable
}

deadline=$((SECONDS + TIMEOUT))
until control_ready; do
  if [ "$(docker inspect -f '{{.State.Running}}' cloud-control 2>/dev/null)" != true ] || \
     [ "$SECONDS" -ge "$deadline" ]; then
    printf '%s\n' 'cloud-control is not ready; last log lines:' >&2
    docker logs --tail 20 cloud-control >&2 2>&1 || true
    exit 1
  fi
  sleep 1
done

# The fixed request ID makes create idempotent: a rerun returns the same server.
if ! created="$(bash "$CLI" create "$NAME" --accept-eula --request-id "up-$NAME" 2>&1)"; then
  printf '%s\n' "$created" >&2
  if printf '%s' "$created" | grep -q capacity_unavailable; then
    printf '%s\n' 'this installation already holds a server that up.sh did not create;' \
      'manage it with bash infra/compose/cloud.sh <start|stop|status> <server_id>,' \
      'or erase everything with bash infra/compose/destroy.sh --yes (deletes the world)' >&2
  fi
  exit 1
fi
server_id="$(printf '%s' "$created" | field server_id)"

state="$(bash "$CLI" status "$server_id" | field state)"
if [ "$state" = stopped ] || [ "$state" = stopping ]; then
  bash "$CLI" start "$server_id" >/dev/null
fi

until status="$(bash "$CLI" status "$server_id")" && [ "$(printf '%s' "$status" | field state)" = running ]; do
  [ "$SECONDS" -lt "$deadline" ] || { printf '%s\n' "server not running after ${TIMEOUT}s: $status" >&2; exit 1; }
  sleep 2
done

host="$(printf '%s' "$status" | field host)"
port="$(printf '%s' "$status" | sed -n 's/.*"port":\([0-9]*\).*/\1/p')"
printf 'READY: the Minecraft server is running and accepts players; nothing else to start.\n'
printf 'server_id=%s\nendpoint=%s:%s\n' "$server_id" "$host" "$port"
