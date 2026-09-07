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
GAME_NODE_ADDRESS=10.0.0.20
GAME_CLUSTER_SOURCE_ADDRESS=192.0.2.20
GAME_DIRECT_ADDRESS=198.51.100.20
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
load_two_host_config "$missing_secret" public
if grep -q 'test-postgres-password-151' "$TEST_ROOT/stdout" "$TEST_ROOT/stderr"; then
  echo "FAIL: configuration error disclosed a secret" >&2
  exit 1
fi

for missing_address_name in GAME_NODE_ADDRESS GAME_CLUSTER_SOURCE_ADDRESS GAME_DIRECT_ADDRESS; do
  missing_address="$TEST_ROOT/missing-${missing_address_name}.env"
  grep -v "^${missing_address_name}=" "$valid_config" >"$missing_address"
  expect_failure "missing $missing_address_name" load_two_host_config "$missing_address"
done

for unsafe_path in / /var/lib /home/operator/data; do
  unsafe_config="$TEST_ROOT/unsafe.env"
  sed "s#^GAME_DATA_PATH=.*#GAME_DATA_PATH=$unsafe_path#" "$valid_config" >"$unsafe_config"
  expect_failure "unsafe data path $unsafe_path" load_two_host_config "$unsafe_config"
done

for invalid_assignment in \
  'CONTROL_PRIVATE_ADDRESS=999.0.2.10' \
  'GAME_NODE_ADDRESS=999.0.2.20' \
  'GAME_CLUSTER_SOURCE_ADDRESS=999.0.2.21' \
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
for script in "$K3S_DIR"/*.sh "$SCRIPT_DIR"/*.sh; do
  if ! bash -n "$script"; then
    echo "FAIL: shell syntax check failed for $script" >&2
    exit 1
  fi
done

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
expect_file_contains "$K3S_DIR/install-game.sh" 'GAME_NODE_ADDRESS'
expect_file_contains "$K3S_DIR/install-game.sh" '--node-ip=\$\{GAME_NODE_ADDRESS\}'
expect_file_excludes "$K3S_DIR/install-game.sh" '--node-ip=\$\{GAME_CLUSTER_SOURCE_ADDRESS\}'

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

rendered_dir="$TEST_ROOT/rendered"
mkdir "$rendered_dir"
"$SCRIPT_DIR/render.sh" "$valid_config" "$rendered_dir"

control_manifest="$rendered_dir/10-control.yaml"
game_storage_manifest="$rendered_dir/20-game-storage.yaml"
game_manifest="$rendered_dir/30-game.yaml"

expect_file_contains "$control_manifest" 'image: postgres:17\.6-bookworm@sha256:[a-f0-9]{64}'
expect_file_contains "$control_manifest" 'type: ClusterIP'
expect_file_excludes "$control_manifest" 'type: (NodePort|LoadBalancer)'
expect_file_excludes "$control_manifest" 'hostPort: 5432'
expect_file_contains "$control_manifest" 'hostPort: 3000'
expect_file_contains "$control_manifest" 'cloud\.example/role: control'
expect_file_contains "$control_manifest" 'automountServiceAccountToken: false'
expect_file_contains "$game_storage_manifest" 'path: /var/lib/cloud/tes-151/minecraft'
expect_file_contains "$game_storage_manifest" 'storage: 10Gi'
expect_file_contains "$game_manifest" 'cloud\.example/role: game'
expect_file_contains "$game_manifest" 'hostPort: 25565'
expect_file_contains "$game_manifest" 'memory: 3Gi'
expect_file_contains "$game_manifest" 'cpu: "2"'
expect_file_contains "$game_manifest" 'image: itzg/minecraft-server@sha256:efa878d'
expect_file_excludes "$rendered_dir/10-control.yaml" 'test-(postgres-password|machine-token)-151'
expect_file_excludes "$rendered_dir/20-game-storage.yaml" 'test-(postgres-password|machine-token)-151'
expect_file_excludes "$rendered_dir/30-game.yaml" 'test-(postgres-password|machine-token)-151'
if grep -R '@[A-Z_][A-Z_]*@' "$rendered_dir" >/dev/null; then
  echo "FAIL: rendered manifests contain unresolved placeholders" >&2
  exit 1
fi

touch "$rendered_dir/not-empty"
expect_failure "non-empty render directory" "$SCRIPT_DIR/render.sh" "$valid_config" "$rendered_dir"

RESET_SCRIPT="$SCRIPT_DIR/reset-host.sh"
PREPARE_SCRIPT="$SCRIPT_DIR/prepare-host.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy.sh"
VERIFY_SCRIPT="$SCRIPT_DIR/verify.sh"

expect_file_contains "$RESET_SCRIPT" 'k3s-uninstall\.sh'
expect_file_contains "$RESET_SCRIPT" 'k3s-agent-uninstall\.sh'
expect_file_contains "$RESET_SCRIPT" 'unrelated'
expect_file_contains "$RESET_SCRIPT" 'find .* -mindepth 1'
expect_file_excludes "$RESET_SCRIPT" 'rm -rf[[:space:]]+[/~]'
expect_failure "invalid reset role" "$RESET_SCRIPT" invalid "$valid_config"

expect_file_contains "$PREPARE_SCRIPT" 'install -d'
expect_file_contains "$PREPARE_SCRIPT" 'GAME_HOST_RESERVED_CPU'
expect_file_contains "$PREPARE_SCRIPT" 'GAME_HOST_RESERVED_MEMORY_GIB'
expect_file_contains "$PREPARE_SCRIPT" 'GAME_HOST_RESERVED_DISK_GIB'

expect_file_contains "$DEPLOY_SCRIPT" 'mktemp -d'
expect_file_contains "$DEPLOY_SCRIPT" 'kubectl create secret generic'
expect_file_contains "$DEPLOY_SCRIPT" '--from-env-file='
expect_file_excludes "$DEPLOY_SCRIPT" '--from-literal='
expect_file_contains "$DEPLOY_SCRIPT" 'docker build'
expect_file_contains "$DEPLOY_SCRIPT" 'k3s ctr images import'
expect_file_contains "$DEPLOY_SCRIPT" 'rollout status'

expect_file_contains "$VERIFY_SCRIPT" 'CLOUD_MACHINE_TOKEN'
expect_file_contains "$VERIFY_SCRIPT" 'cloud-postgres.*ClusterIP'
expect_file_contains "$VERIFY_SCRIPT" 'GAME_HOST_RESERVED_CPU'
expect_file_contains "$VERIFY_SCRIPT" 'GAME_NODE_ADDRESS'
expect_file_contains "$VERIFY_SCRIPT" 'GAME_DIRECT_ADDRESS'
expect_file_excludes "$VERIFY_SCRIPT" 'POSTGRES_PASSWORD.*echo|echo.*POSTGRES_PASSWORD'

RUNBOOK="$SCRIPT_DIR/README.md"
expect_file_contains "$RUNBOOK" 'Ubuntu 24\.04'
expect_file_contains "$RUNBOOK" 'clean (clone|checkout)'
expect_file_contains "$RUNBOOK" 'operator-owned'
expect_file_contains "$RUNBOOK" 'MINECRAFT_EULA=TRUE'
expect_file_contains "$RUNBOOK" 'reset-host\.sh'
expect_file_contains "$RUNBOOK" 'deploy\.sh'
expect_file_contains "$RUNBOOK" 'verify\.sh'
expect_file_contains "$RUNBOOK" 'reapply|second pass'
expect_file_contains "$RUNBOOK" '2 GiB.*heap'
expect_file_contains "$RUNBOOK" '3 GiB.*container'
expect_file_contains "$RUNBOOK" '10 GiB.*(storage|PVC)'
expect_file_contains "$RUNBOOK" 'reserve'
expect_file_contains "$RUNBOOK" 'direct.*TCP'
expect_file_contains "$RUNBOOK" 'GAME_NODE_ADDRESS'
expect_file_contains "$RUNBOOK" 'GAME_CLUSTER_SOURCE_ADDRESS'
expect_file_contains "$RUNBOOK" 'GAME_DIRECT_ADDRESS'
expect_file_contains "$RUNBOOK" 'Troubleshooting'
expect_file_contains "$RUNBOOK" 'TES-152'
expect_file_contains "$RUNBOOK" 'F2/F3'

for linked_file in \
  "$SCRIPT_DIR/../../README.md" \
  "$SCRIPT_DIR/../README.md" \
  "$SCRIPT_DIR/../k3s/README.md" \
  "$SCRIPT_DIR/config.example.env"; do
  if [ ! -f "$linked_file" ]; then
    echo "FAIL: documented relative target is missing: $linked_file" >&2
    exit 1
  fi
done

echo "two-host tests passed"
