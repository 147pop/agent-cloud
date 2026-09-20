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

while [ $# -gt 0 ]; do
  case "$1" in
    --accept-eula) ACCEPT_EULA=1 ;;
    --clone)
      CLONE_DIR="${2:?--clone needs a directory}"
      shift
      ;;
    --fresh) FRESH=1 ;;
    --no-install) NO_INSTALL=1 ;;
    *)
      printf '%s\n' "unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -n "$CLONE_DIR" ]; then
  if [ -e "$CLONE_DIR" ]; then
    printf '%s\n' "$CLONE_DIR already exists" >&2
    exit 1
  fi
  git clone --quiet "$REPOSITORY_ROOT" "$CLONE_DIR"
  reexec=(bash "$CLONE_DIR/infra/compose/journey.sh")
  if [ "$ACCEPT_EULA" = 1 ]; then reexec+=(--accept-eula); fi
  if [ "$FRESH" = 1 ]; then reexec+=(--fresh); fi
  if [ "$NO_INSTALL" = 1 ]; then reexec+=(--no-install); fi
  exec "${reexec[@]}"
fi

JOURNEY_START=$(date +%s)
RUN_ID="journey-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

step_start=0
step() {
  step_start=$(date +%s)
  printf '%s\n' "== $1"
}
ok() { printf '   ok (%ss)\n' "$(( $(date +%s) - step_start ))"; }

expect_eq() {
  if [ "$1" != "$2" ]; then
    printf '   FAIL: %s: expected %s, got %s\n' "${3:-value}" "$2" "$1" >&2
    exit 1
  fi
}

json() { # file expression -> prints String(expression(d))
  node -e 'const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const f = new Function("d", "return " + process.argv[2]);
    process.stdout.write(String(f(d)));' "$1" "$2"
}

step 'preflight'
docker compose version >/dev/null
node --version >/dev/null
node --check "$SCRIPT_DIR/protocol-status.mjs"
ok

step 'operator configuration'
if [ ! -f "$ENV_FILE" ]; then
  if [ "$ACCEPT_EULA" != 1 ]; then
    printf '%s\n' 'pass --accept-eula to generate a .env that accepts the Minecraft EULA' >&2
    exit 1
  fi
  (
    umask 177
    {
      printf 'CLOUD_MACHINE_TOKEN=journey-%s\n' \
        "$(node -e 'process.stdout.write(require("crypto").randomBytes(16).toString("hex"))')"
      printf 'POSTGRES_PASSWORD=%s\n' \
        "$(node -e 'process.stdout.write(require("crypto").randomBytes(16).toString("hex"))')"
      printf 'MINECRAFT_EULA=TRUE\n'
    } >"$ENV_FILE"
  )
  printf '%s\n' '   generated .env with random credentials (not printed)'
else
  printf '%s\n' '   reusing existing .env (values not printed)'
fi
set -a
. "$ENV_FILE"
set +a
: "${CLOUD_MACHINE_TOKEN:?CLOUD_MACHINE_TOKEN missing in .env}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD missing in .env}"
CONTROL_URL="http://127.0.0.1:${CONTROL_API_PORT:-3000}"
export CLOUD_CONTROL_URL="$CONTROL_URL"
ok

step 'clean Compose state'
if docker ps -a --filter 'name=cloud-' --format '{{.Names}}' | grep -q .; then
  if [ "$FRESH" = 1 ]; then
    bash "$SCRIPT_DIR/destroy.sh" --yes
  else
    printf '%s\n' 'existing cloud-* containers found; rerun with --fresh to destroy named volumes first' >&2
    exit 1
  fi
fi
ok

step 'install and build'
if [ "$NO_INSTALL" = 0 ]; then
  ( cd "$REPOSITORY_ROOT" && npm ci --no-audit --no-fund )
  ( cd "$REPOSITORY_ROOT" && npm run build )
fi
ok

step 'Compose setup'
compose=(docker compose --env-file "$ENV_FILE" -f "$REPOSITORY_ROOT/compose.yaml")
"${compose[@]}" build cloud-control
bash "$SCRIPT_DIR/setup.sh"
ok

step 'control API readiness'
waited=0
until curl -fsS "$CONTROL_URL/healthz" >/dev/null 2>&1; do
  if [ "$waited" -ge 60 ]; then
    printf '%s\n' '   FAIL: control API not ready within 60s' >&2
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done
ok

rest() { # method path [json-body] -> prints HTTP status, body in "$TMP/body"
  if [ $# -ge 3 ]; then
    curl -sS -o "$TMP/body" -w '%{http_code}' -X "$1" "$CONTROL_URL$2" \
      -H "Authorization: Bearer $CLOUD_MACHINE_TOKEN" \
      -H 'content-type: application/json' -d "$3"
  else
    curl -sS -o "$TMP/body" -w '%{http_code}' -X "$1" "$CONTROL_URL$2" \
      -H "Authorization: Bearer $CLOUD_MACHINE_TOKEN"
  fi
}

mcp() { # method params-json -> reply in "$TMP/body"
  curl -sS -o "$TMP/body" "$CONTROL_URL/mcp" \
    -H "Authorization: Bearer $CLOUD_MACHINE_TOKEN" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}

cli() { # cloud args... -> prints exit code; last stdout line in "$TMP/cli-last"
  if npm run -s cloud -- "$@" >"$TMP/cli" 2>"$TMP/cli-err"; then
    code=0
  else
    code=$?
  fi
  sed '/^$/d' "$TMP/cli" | tail -n 1 >"$TMP/cli-last"
  printf '%s' "$code"
}

wait_state() { # wanted timeout_seconds -> prints seconds waited
  wanted="$1"
  timeout_s="$2"
  waited=0
  while :; do
    code="$(rest GET "$STATUS_PATH")"
    expect_eq "$code" 200 'status HTTP'
    if [ "$(json "$TMP/body" 'd.state')" = "$wanted" ]; then
      printf '%s' "$waited"
      return
    fi
    if [ "$waited" -ge "$timeout_s" ]; then
      printf '   FAIL: timed out after %ss waiting for %s\n' "$waited" "$wanted" >&2
      exit 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

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
