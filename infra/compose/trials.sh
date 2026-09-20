#!/usr/bin/env bash
set -euo pipefail

# Automates the F4.2 trials against one Compose installation: three distinct
# creates race for the single slot, repeated mutation keys return the one
# recorded effect, changed bodies conflict, control-process restarts around
# real Docker operations converge, and a force-recreated game container keeps
# the same world and endpoint. After each trial the observed Docker container
# state, the durable PostgreSQL state and the endpoint reported to clients
# must agree. See infra/compose/README.md.
#
# usage: trials.sh [--accept-eula] [--clone DIR] [--fresh] [--no-install]
#   flags behave exactly as in infra/compose/journey.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$REPOSITORY_ROOT/.env}"

ACCEPT_EULA=0
CLONE_DIR=""
FRESH=0
NO_INSTALL=0

. "$SCRIPT_DIR/journey-lib.sh"
parse_common_args "$@"
reexec_in_clone trials.sh

TRIALS_START=$(date +%s)
RUN_ID="trials-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

game_container_count() {
  docker ps -a --format '{{.Names}}' | { grep -cx cloud-game-1 || true; }
}

assert_agreement() { # wanted — API status, durable rows and Docker must agree
  wanted="$1"
  code="$(rest GET "$STATUS_PATH")"
  expect_eq "$code" 200 'status HTTP'
  expect_eq "$(json "$TMP/body" 'd.state')" "$wanted" 'API state'
  expect_eq "$(psql_scalar "SELECT state FROM servers WHERE id = '$SERVER_ID'")" \
    "$wanted" 'durable state'
  expect_eq "$(psql_scalar "SELECT desired_state FROM servers WHERE id = '$SERVER_ID'")" \
    "$wanted" 'desired state'
  expect_eq "$(game_container_count)" 1 'cloud-game-1 container count'
  docker_status="$(docker inspect cloud-game-1 --format '{{.State.Status}}')"
  active_runs="$(psql_scalar \
    "SELECT count(*) FROM runs WHERE state IN ('queued','provisioning','running','stopping')")"
  if [ "$wanted" = running ]; then
    expect_eq "$docker_status" running 'docker state'
    expect_eq "$(docker inspect cloud-game-1 --format '{{.State.Health.Status}}')" \
      healthy 'docker health'
    expect_eq "$(json "$TMP/body" 'd.endpoint.host')" "$ENDPOINT_HOST" 'endpoint host'
    expect_eq "$(json "$TMP/body" 'd.endpoint.port')" "$ENDPOINT_PORT" 'endpoint port'
    expect_eq "$active_runs" 1 'active runs'
  else
    expect_eq "$docker_status" exited 'docker state'
    expect_eq "$(json "$TMP/body" 'd.endpoint === undefined ? "absent" : "present"')" \
      absent 'endpoint field'
    expect_eq "$active_runs" 0 'active runs'
  fi
}

protocol_ping() {
  node "$SCRIPT_DIR/protocol-status.mjs" --host "$ENDPOINT_HOST" --port "$ENDPOINT_PORT" \
    >"$TMP/protocol"
  expect_eq "$(json "$TMP/protocol" 'd.protocol')" 776 'protocol version'
}

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

step 'competing creates race for the single slot'
for i in 1 2 3; do
  curl -sS -o "$TMP/race-$i-body" -w '%{http_code}' -X POST "$CONTROL_URL/v1/servers" \
    -H "Authorization: Bearer $CLOUD_MACHINE_TOKEN" \
    -H 'content-type: application/json' \
    -d "{\"client_request_id\":\"$RUN_ID-race-$i\",\"name\":\"race-$i\",\"eula_accepted\":true}" \
    >"$TMP/race-$i-code" &
done
wait
accepted=0
for i in 1 2 3; do
  race_code="$(cat "$TMP/race-$i-code")"
  if [ "$race_code" = 202 ]; then
    accepted=$((accepted + 1))
    WINNER="$i"
  else
    expect_eq "$race_code" 409 "race-$i HTTP status"
    expect_eq "$(json "$TMP/race-$i-body" 'd.error')" capacity_unavailable "race-$i error"
  fi
done
expect_eq "$accepted" 1 'accepted creates'
SERVER_ID="$(json "$TMP/race-$WINNER-body" 'd.server_id')"
STATUS_PATH="$(json "$TMP/race-$WINNER-body" 'd.status_url')"
WINNER_KEY="$RUN_ID-race-$WINNER"
WINNER_NAME="race-$WINNER"
expect_eq "$(psql_scalar 'SELECT count(*) FROM servers')" 1 'server rows'
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 1 'claimed keys'
printf '   race winner: request %s\n' "$WINNER_KEY"
ok

step 'status until running'
waited="$(wait_state running 300)"
ENDPOINT_HOST="$(json "$TMP/body" 'd.endpoint && d.endpoint.host')"
ENDPOINT_PORT="$(json "$TMP/body" 'd.endpoint && d.endpoint.port')"
printf '   endpoint %s:%s after %ss\n' "$ENDPOINT_HOST" "$ENDPOINT_PORT" "$waited"
protocol_ping
assert_agreement running
ok

step 'idempotent create replay returns the recorded effect'
code="$(rest POST /v1/servers \
  "{\"client_request_id\":\"$WINNER_KEY\",\"name\":\"$WINNER_NAME\",\"eula_accepted\":true}")"
expect_eq "$code" 202 'HTTP status'
expect_eq "$(json "$TMP/body" 'd.server_id')" "$SERVER_ID" 'replayed server_id'
expect_eq "$(json "$TMP/body" 'd.request_id')" "$WINNER_KEY" 'replayed request_id'
expect_eq "$(psql_scalar 'SELECT count(*) FROM servers')" 1 'server rows'
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 1 'claimed keys'
ok

step 'changed body on the same key conflicts'
code="$(rest POST /v1/servers \
  "{\"client_request_id\":\"$WINNER_KEY\",\"name\":\"changed-name\",\"eula_accepted\":true}")"
expect_eq "$code" 409 'HTTP status'
expect_eq "$(json "$TMP/body" 'd.error')" idempotency_key_reused 'error code'
ok

step 'same key on a different operation conflicts'
code="$(rest POST "$STATUS_PATH/stop" "{\"client_request_id\":\"$WINNER_KEY\"}")"
expect_eq "$code" 409 'HTTP status'
expect_eq "$(json "$TMP/body" 'd.error')" idempotency_key_reused 'error code'
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 1 'claimed keys'
assert_agreement running
ok

step 'world marker'
MARKER="$RUN_ID"
docker exec cloud-game-1 sh -c 'printf %s "$1" > /data/trials-marker' _ "$MARKER"
expect_eq "$(docker exec cloud-game-1 cat /data/trials-marker)" "$MARKER" 'marker content'
ok

step 'REST stop, then replay the same mutation key'
code="$(rest POST "$STATUS_PATH/stop" "{\"client_request_id\":\"$RUN_ID-stop-1\"}")"
expect_eq "$code" 202 'HTTP status'
waited="$(wait_state stopped 180)"
printf '   stopped after %ss\n' "$waited"
assert_agreement stopped
code="$(rest POST "$STATUS_PATH/stop" "{\"client_request_id\":\"$RUN_ID-stop-1\"}")"
expect_eq "$code" 202 'replayed HTTP status'
expect_eq "$(json "$TMP/body" 'd.server_id')" "$SERVER_ID" 'replayed server_id'
expect_eq "$(json "$TMP/body" 'd.state')" stopping 'recorded state'
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 2 'claimed keys'
ok

step 'control restart while the start converges'
code="$(rest POST "$STATUS_PATH/start" "{\"client_request_id\":\"$RUN_ID-start-1\"}")"
expect_eq "$code" 202 'HTTP status'
docker restart -t 2 cloud-control >/dev/null
wait_control
waited="$(wait_state running 300)"
printf '   running after %ss with a mid-operation control restart\n' "$waited"
assert_agreement running
protocol_ping
expect_eq "$(docker exec cloud-game-1 cat /data/trials-marker)" "$MARKER" 'marker preserved'
code="$(rest POST "$STATUS_PATH/start" "{\"client_request_id\":\"$RUN_ID-start-1\"}")"
expect_eq "$code" 202 'replayed HTTP status'
expect_eq "$(json "$TMP/body" 'd.server_id')" "$SERVER_ID" 'replayed server_id'
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 3 'claimed keys'
ok

step 'control restart while the stop converges'
code="$(rest POST "$STATUS_PATH/stop" "{\"client_request_id\":\"$RUN_ID-stop-2\"}")"
expect_eq "$code" 202 'HTTP status'
docker restart -t 2 cloud-control >/dev/null
wait_control
waited="$(wait_state stopped 240)"
printf '   stopped after %ss with a mid-operation control restart\n' "$waited"
assert_agreement stopped
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 4 'claimed keys'
ok

step 'start again for container recreation'
code="$(rest POST "$STATUS_PATH/start" "{\"client_request_id\":\"$RUN_ID-start-2\"}")"
expect_eq "$code" 202 'HTTP status'
waited="$(wait_state running 300)"
printf '   running after %ss\n' "$waited"
assert_agreement running
ok

step 'safe container recreation keeps the same world and endpoint'
CID_BEFORE="$(docker inspect cloud-game-1 --format '{{.Id}}')"
dc up -d --force-recreate game-1 >/dev/null
CID_AFTER="$(docker inspect cloud-game-1 --format '{{.Id}}')"
if [ "$CID_BEFORE" = "$CID_AFTER" ]; then
  printf '%s\n' '   FAIL: container id did not change after force-recreate' >&2
  exit 1
fi
# The durable state can still read running while the new container boots;
# wait for its healthcheck first, then for the reconciler to agree.
waited=0
until [ "$(docker inspect cloud-game-1 --format '{{.State.Health.Status}}' 2>/dev/null || true)" = healthy ]; do
  if [ "$waited" -ge 300 ]; then
    printf '   FAIL: recreated container not healthy within 300s\n' >&2
    exit 1
  fi
  sleep 2
  waited=$((waited + 2))
done
printf '   recreated container healthy after %ss\n' "$waited"
wait_state running 60 >/dev/null
assert_agreement running
protocol_ping
expect_eq "$(docker exec cloud-game-1 cat /data/trials-marker)" "$MARKER" 'marker preserved'
expect_eq "$(psql_scalar 'SELECT count(*) FROM idempotency_keys')" 5 'claimed keys'
ok

step 'single-writer invariants hold after every trial'
expect_eq "$(game_container_count)" 1 'cloud-game-1 container count'
expect_eq "$(psql_scalar 'SELECT count(*) FROM servers')" 1 'server rows'
expect_eq "$(psql_scalar \
  "SELECT count(*) FROM runs WHERE state IN ('queued','provisioning','running','stopping')")" \
  1 'active runs'
expect_eq "$(docker ps --format '{{.Names}}' | { grep -cx cloud-game-1 || true; })" \
  1 'running game containers'
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

printf '%s\n' "trials complete: $RUN_ID"
printf '%s\n' "server $SERVER_ID at $ENDPOINT_HOST:$ENDPOINT_PORT, stack stopped, volumes preserved"
printf 'total %ss\n' "$(( $(date +%s) - TRIALS_START ))"
