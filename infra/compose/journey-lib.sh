# Shared helpers for the Compose verification scripts (journey.sh, trials.sh).
# Callers set SCRIPT_DIR, REPOSITORY_ROOT and ENV_FILE, initialize the
# ACCEPT_EULA, CLONE_DIR, FRESH and NO_INSTALL flags, then source this file.
# Helpers also read globals the caller creates at run time: TMP, RUN_ID,
# CLOUD_MACHINE_TOKEN, CONTROL_URL and STATUS_PATH.

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

parse_common_args() {
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
}

reexec_in_clone() { # script-name — clone this checkout and rerun the script there
  if [ -z "$CLONE_DIR" ]; then return 0; fi
  if [ -e "$CLONE_DIR" ]; then
    printf '%s\n' "$CLONE_DIR already exists" >&2
    exit 1
  fi
  git clone --quiet "$REPOSITORY_ROOT" "$CLONE_DIR"
  reexec=(bash "$CLONE_DIR/infra/compose/$1")
  if [ "$ACCEPT_EULA" = 1 ]; then reexec+=(--accept-eula); fi
  if [ "$FRESH" = 1 ]; then reexec+=(--fresh); fi
  if [ "$NO_INSTALL" = 1 ]; then reexec+=(--no-install); fi
  exec "${reexec[@]}"
}

ensure_env_file() {
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
}

load_env() {
  set -a
  . "$ENV_FILE"
  set +a
  : "${CLOUD_MACHINE_TOKEN:?CLOUD_MACHINE_TOKEN missing in .env}"
  : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD missing in .env}"
  CONTROL_URL="http://127.0.0.1:${CONTROL_API_PORT:-3000}"
  export CLOUD_CONTROL_URL="$CONTROL_URL"
}

clean_compose_state() {
  if docker ps -a --filter 'name=cloud-' --format '{{.Names}}' | grep -q .; then
    if [ "$FRESH" = 1 ]; then
      bash "$SCRIPT_DIR/destroy.sh" --yes
    else
      printf '%s\n' 'existing cloud-* containers found; rerun with --fresh to destroy named volumes first' >&2
      exit 1
    fi
  fi
}

install_and_build() {
  if [ "$NO_INSTALL" = 0 ]; then
    ( cd "$REPOSITORY_ROOT" && npm ci --no-audit --no-fund )
    ( cd "$REPOSITORY_ROOT" && npm run build )
  fi
}

dc() {
  docker compose --env-file "$ENV_FILE" -f "$REPOSITORY_ROOT/compose.yaml" "$@"
}

compose_setup() {
  dc build cloud-control
  bash "$SCRIPT_DIR/setup.sh"
}

wait_control() {
  waited=0
  until curl -fsS "$CONTROL_URL/healthz" >/dev/null 2>&1; do
    if [ "$waited" -ge 60 ]; then
      printf '%s\n' '   FAIL: control API not ready within 60s' >&2
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

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
  if ( cd "$REPOSITORY_ROOT" && npm run -s cloud -- "$@" ) >"$TMP/cli" 2>"$TMP/cli-err"; then
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

psql_scalar() { # sql -> single-column result via the postgres container
  docker exec cloud-postgres psql -U cloud -d cloud -tA -c "$1"
}
