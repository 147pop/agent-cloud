#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

write_valid_config() {
  local destination="$1"
  cat >"$destination" <<'EOF'
K3S_VERSION=v1.36.4+k3s1
CONTROL_NODE_NAME=control-1
GAME_NODE_NAME=game-1
CONTROL_PRIVATE_ADDRESS=192.0.2.10
GAME_PRIVATE_ADDRESS=192.0.2.20
CONTROL_API_CLIENT_CIDR=192.0.2.30/32
CONTROL_API_PORT=3000
GAME_PORT=25565
POSTGRES_DATA_PATH=/var/lib/cloud/tes-151/postgres
GAME_DATA_PATH=/var/lib/cloud/tes-151/minecraft
POSTGRES_STORAGE_GIB=10
GAME_STORAGE_GIB=10
GAME_CPU=2
GAME_JAVA_HEAP=2G
GAME_MEMORY=3Gi
GAME_HOST_RESERVED_CPU=2
GAME_HOST_RESERVED_MEMORY_GIB=4
GAME_HOST_RESERVED_DISK_GIB=10
MINECRAFT_EULA=TRUE
POSTGRES_PASSWORD=test-postgres-password-151
CLOUD_MACHINE_TOKEN=test-machine-token-151
EOF
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
}

expect_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Eq -- "$pattern" "$file"; then
    echo "FAIL: $file does not contain expected pattern: $pattern" >&2
    exit 1
  fi
}

expect_file_excludes() {
  local file="$1"
  local pattern="$2"
  if grep -Eq -- "$pattern" "$file"; then
    echo "FAIL: $file contains forbidden pattern: $pattern" >&2
    exit 1
  fi
}

valid_config="$TEST_ROOT/valid.env"
write_valid_config "$valid_config"
load_two_host_config "$valid_config"

missing_secret="$TEST_ROOT/missing-secret.env"
grep -v '^CLOUD_MACHINE_TOKEN=' "$valid_config" >"$missing_secret"
expect_failure "missing machine token" load_two_host_config "$missing_secret"
if grep -q 'test-postgres-password-151' "$TEST_ROOT/stdout" "$TEST_ROOT/stderr"; then
  echo "FAIL: configuration error disclosed a secret" >&2
  exit 1
fi

for unsafe_path in / /var/lib /home/operator/data; do
  unsafe_config="$TEST_ROOT/unsafe.env"
  sed "s#^GAME_DATA_PATH=.*#GAME_DATA_PATH=$unsafe_path#" "$valid_config" >"$unsafe_config"
  expect_failure "unsafe data path $unsafe_path" load_two_host_config "$unsafe_config"
done

for invalid_assignment in \
  'CONTROL_PRIVATE_ADDRESS=999.0.2.10' \
  'CONTROL_API_CLIENT_CIDR=192.0.2.30/99' \
  'CONTROL_API_PORT=0' \
  'GAME_PORT=65536' \
  'GAME_CPU=zero' \
  'GAME_MEMORY=3072' \
  'GAME_NODE_NAME=GAME_1' \
  'MINECRAFT_EULA=FALSE'; do
  variable="${invalid_assignment%%=*}"
  invalid_config="$TEST_ROOT/invalid-${variable}.env"
  sed "s#^${variable}=.*#${invalid_assignment}#" "$valid_config" >"$invalid_config"
  expect_failure "invalid $variable" load_two_host_config "$invalid_config"
done

K3S_DIR="$SCRIPT_DIR/../k3s"
expect_file_contains "$K3S_DIR/install-control.sh" 'v1\.36\.4\+k3s1'
expect_file_contains "$K3S_DIR/install-control.sh" 'INSTALL_K3S_VERSION'
expect_file_contains "$K3S_DIR/install-control.sh" '--node-name='
expect_file_contains "$K3S_DIR/install-control.sh" '--node-ip='
expect_file_contains "$K3S_DIR/install-control.sh" 'NODE_LABEL=.*cloud\.example/role=control'
expect_file_contains "$K3S_DIR/install-control.sh" '--node-label='
expect_file_excludes "$K3S_DIR/install-control.sh" 'cat /var/lib/rancher/k3s/server/node-token'

expect_file_contains "$K3S_DIR/install-game.sh" 'v1\.36\.4\+k3s1'
expect_file_contains "$K3S_DIR/install-game.sh" 'INSTALL_K3S_VERSION'
expect_file_contains "$K3S_DIR/install-game.sh" '--node-name='
expect_file_contains "$K3S_DIR/install-game.sh" '--node-ip='

expect_file_contains "$K3S_DIR/firewall-control.sh" 'API_CLIENT_CIDR'
expect_file_contains "$K3S_DIR/firewall-control.sh" 'CONTROL_API_PORT'
expect_file_contains "$K3S_DIR/firewall-game.sh" 'GAME_PORT'
expect_file_contains "$K3S_DIR/verify.sh" 'kubectl wait'
expect_file_contains "$K3S_DIR/verify.sh" 'CONTROL_NODE_NAME'
expect_file_contains "$K3S_DIR/verify.sh" 'GAME_NODE_NAME'

DOCKERFILE="$SCRIPT_DIR/../../apps/cloud-control/Dockerfile"
expect_file_contains "$DOCKERFILE" '^FROM node:22\.20\.0-bookworm-slim@sha256:[a-f0-9]{64} AS build$'
expect_file_contains "$DOCKERFILE" '^RUN npm ci$'
expect_file_contains "$DOCKERFILE" '^USER node$'
expect_file_contains "$DOCKERFILE" 'dist/src'

echo "two-host tests passed"
