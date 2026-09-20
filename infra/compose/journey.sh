#!/usr/bin/env bash
set -euo pipefail

# Automates the F4.1 agent-to-play journey against one Compose installation:
# clean state, setup, typed errors, REST create and status polling, Minecraft
# protocol readiness, MCP tools, CLI use, a world marker across stop and
# start, second-create capacity and clean shutdown. See infra/compose/README.md.
#
# usage: journey.sh [--accept-eula] [--clone DIR] [--fresh] [--no-install]
#   --accept-eula  generate a missing .env that accepts the Minecraft EULA
#   --clone DIR    clone this checkout to DIR first and run the journey there
#   --fresh        destroy existing named volumes when cloud-* containers exist
#   --no-install   skip npm ci and npm run build (already installed checkout)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"

ACCEPT_EULA=0
CLONE_DIR=""
FRESH=0
NO_INSTALL=0

. "$SCRIPT_DIR/journey-lib.sh"
parse_common_args "$@"
reexec_in_clone journey.sh

JOURNEY_START=$(date +%s)
RUN_ID="journey-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

step 'preflight'
docker compose version >/dev/null
node --version >/dev/null
node --check "$SCRIPT_DIR/protocol-status.mjs"
ok

step 'operator configuration'
ensure_env_file
load_env
ok

step 'clean Compose state'
clean_compose_state
ok

step 'install and build'
install_and_build
ok

step 'Compose setup'
compose_setup
ok

step 'control API readiness'
wait_control
ok

step 'typed error: REST create without EULA acceptance'
code="$(rest POST /v1/servers "{\"client_request_id\":\"$RUN_ID-eula\",\"name\":\"one\"}")"
expect_eq "$code" 409 'HTTP status'
expect_eq "$(json "$TMP/body" 'd.error')" action_required 'error code'
expect_eq "$(json "$TMP/body" 'd.action_required')" accept_eula 'action required'
ok

step 'REST create one (EULA accepted)'
code="$(rest POST /v1/servers "{\"client_request_id\":\"$RUN_ID-create\",\"name\":\"one\",\"eula_accepted\":true}")"
expect_eq "$code" 202 'HTTP status'
SERVER_ID="$(json "$TMP/body" 'd.server_id')"
STATUS_PATH="$(json "$TMP/body" 'd.status_url')"
if [ -z "$SERVER_ID" ] || [ "$SERVER_ID" = "undefined" ]; then
  printf '%s\n' '   FAIL: create response missing server_id' >&2
  exit 1
fi
ok

step 'status until running'
waited="$(wait_state running 300)"
ENDPOINT_HOST="$(json "$TMP/body" 'd.endpoint && d.endpoint.host')"
ENDPOINT_PORT="$(json "$TMP/body" 'd.endpoint && d.endpoint.port')"
if [ "$ENDPOINT_HOST" = "undefined" ] || [ "$ENDPOINT_PORT" = "undefined" ]; then
  printf '%s\n' '   FAIL: running status missing endpoint' >&2
  exit 1
fi
printf '   endpoint %s:%s after %ss\n' "$ENDPOINT_HOST" "$ENDPOINT_PORT" "$waited"
ok

step 'Minecraft protocol readiness'
node "$SCRIPT_DIR/protocol-status.mjs" --host "$ENDPOINT_HOST" --port "$ENDPOINT_PORT" >"$TMP/protocol"
expect_eq "$(json "$TMP/protocol" 'd.protocol')" 776 'protocol version'
printf '   %s players online, version %s\n' \
  "$(json "$TMP/protocol" 'd.players_online')" "$(json "$TMP/protocol" 'd.version')"
ok

step 'MCP initialize and tools/list'
mcp initialize '{}'
expect_eq "$(json "$TMP/body" 'd.result.serverInfo.name')" cloud-control 'server info'
mcp tools/list '{}'
expect_eq "$(json "$TMP/body" 'd.result.tools.map(t=>t.name).sort().join(",")')" \
  'minecraft_create,minecraft_start,minecraft_status,minecraft_stop' 'tool list'
ok

step 'MCP minecraft_status'
mcp tools/call "{\"name\":\"minecraft_status\",\"arguments\":{\"server_id\":\"$SERVER_ID\"}}"
expect_eq "$(json "$TMP/body" 'd.result.structuredContent.state')" running 'state'
expect_eq "$(json "$TMP/body" 'd.result.structuredContent.endpoint.host')" "$ENDPOINT_HOST" 'endpoint host'
expect_eq "$(json "$TMP/body" 'd.result.structuredContent.endpoint.port')" "$ENDPOINT_PORT" 'endpoint port'
ok

step 'CLI status'
code="$(cli status "$SERVER_ID")"
expect_eq "$code" 0 'CLI exit'
expect_eq "$(json "$TMP/cli-last" 'd.state')" running 'CLI state'
expect_eq "$(json "$TMP/cli-last" 'd.endpoint.host')" "$ENDPOINT_HOST" 'CLI endpoint host'
ok

step 'typed error: CLI create without --accept-eula'
code="$(cli create one)"
expect_eq "$code" 1 'CLI exit'
if ! grep -q '"action_required":"accept_eula"' "$TMP/cli-err"; then
  printf '%s\n' '   FAIL: expected accept_eula typed error on stderr' >&2
  exit 1
fi
ok

step 'world marker'
MARKER="$RUN_ID"
docker exec cloud-game-1 sh -c 'printf %s "$1" > /data/journey-marker' _ "$MARKER"
expect_eq "$(docker exec cloud-game-1 cat /data/journey-marker)" "$MARKER" 'marker content'
ok

step 'MCP stop and wait for stopped'
mcp tools/call "{\"name\":\"minecraft_stop\",\"arguments\":{\"client_request_id\":\"$RUN_ID-stop\",\"server_id\":\"$SERVER_ID\"}}"
expect_eq "$(json "$TMP/body" 'd.result.structuredContent.request_id ? "accepted" : "missing"')" \
  accepted 'mutation accepted'
waited="$(wait_state stopped 180)"
printf '   stopped after %ss\n' "$waited"
ok

step 'protocol connection refused while stopped'
if node "$SCRIPT_DIR/protocol-status.mjs" \
  --host "$ENDPOINT_HOST" --port "$ENDPOINT_PORT" >/dev/null 2>"$TMP/protocol-err"; then
  printf '%s\n' '   FAIL: protocol connection succeeded while stopped' >&2
  exit 1
fi
if ! grep -q 'ECONNREFUSED' "$TMP/protocol-err"; then
  printf '%s\n' '   FAIL: expected ECONNREFUSED' >&2
  exit 1
fi
ok

step 'CLI start --wait with the same endpoint'
code="$(cli start "$SERVER_ID" --request-id "$RUN_ID-start" --wait)"
expect_eq "$code" 0 'CLI exit'
expect_eq "$(json "$TMP/cli-last" 'd.state')" running 'CLI final state'
expect_eq "$(json "$TMP/cli-last" 'd.endpoint.host')" "$ENDPOINT_HOST" 'endpoint host'
expect_eq "$(json "$TMP/cli-last" 'd.endpoint.port')" "$ENDPOINT_PORT" 'endpoint port'
node "$SCRIPT_DIR/protocol-status.mjs" --host "$ENDPOINT_HOST" --port "$ENDPOINT_PORT" >"$TMP/protocol"
expect_eq "$(json "$TMP/protocol" 'd.protocol')" 776 'protocol version'
expect_eq "$(docker exec cloud-game-1 cat /data/journey-marker)" "$MARKER" 'marker preserved'
ok

step 'second create returns capacity without replacing the server'
code="$(rest POST /v1/servers "{\"client_request_id\":\"$RUN_ID-second\",\"name\":\"two\",\"eula_accepted\":true}")"
expect_eq "$code" 409 'HTTP status'
expect_eq "$(json "$TMP/body" 'd.error')" capacity_unavailable 'error code'
code="$(rest GET "$STATUS_PATH")"
expect_eq "$code" 200 'original server status HTTP'
expect_eq "$(json "$TMP/body" 'd.server_id')" "$SERVER_ID" 'original server id'
expect_eq "$(json "$TMP/body" 'd.state')" running 'original state'
expect_eq "$(json "$TMP/body" 'd.endpoint.host')" "$ENDPOINT_HOST" 'original endpoint'
ok

step 'typed error: wrong token'
code="$(curl -sS -o "$TMP/body" -w '%{http_code}' "$CONTROL_URL/v1/whoami" \
  -H 'Authorization: Bearer wrong-token')"
expect_eq "$code" 401 'HTTP status'
expect_eq "$(json "$TMP/body" 'd.error')" unauthorized 'error code'
ok

step 'clean shutdown preserves named volumes'
bash "$SCRIPT_DIR/shutdown.sh"
if docker ps --filter 'name=cloud-' --format '{{.Names}}' | grep -q .; then
  printf '%s\n' '   FAIL: cloud-* containers still running' >&2
  exit 1
fi
VOLUME_PROJECT="${COMPOSE_PROJECT_NAME:-cloud}"
for volume in game-world postgres-data; do
  if ! docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME_PROJECT}_${volume}$"; then
    printf '   FAIL: volume %s missing\n' "$volume" >&2
    exit 1
  fi
done
ok

printf '%s\n' "journey complete: $RUN_ID"
printf '%s\n' "server $SERVER_ID at $ENDPOINT_HOST:$ENDPOINT_PORT, stack stopped, volumes preserved"
printf 'total %ss\n' "$(( $(date +%s) - JOURNEY_START ))"
