#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

expect_file_contains_fixed() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "FAIL: $file does not contain expected text: $text" >&2
    exit 1
  fi
}

expect_file_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "FAIL: expected file does not exist: $file" >&2
    exit 1
  fi
}

expect_if_block_contains() {
  local file="$1"
  local start_pattern="$2"
  local required_pattern="$3"
  if ! awk -v start="$start_pattern" -v required="$required_pattern" '
    $0 ~ start { in_block = 1 }
    in_block && $0 ~ required { found = 1 }
    in_block && /^[[:space:]]*fi[[:space:]]*$/ { exit(found ? 0 : 1) }
    END { if (!in_block) exit 1 }
  ' "$file"; then
    echo "FAIL: $file block matching $start_pattern lacks $required_pattern" >&2
    exit 1
  fi
}

expect_markdown_fences_valid() {
  local markdown="$1"
  local in_fence=0
  local language=""
  local fence_file=""
  local fence_number=0
  local first_line=""
  local second_line=""
  local last_line=""
  local line
  local trimmed_line

  while IFS= read -r line || [ -n "$line" ]; do
    trimmed_line="${line#"${line%%[![:space:]]*}"}"
    trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"
    if [ "$in_fence" -eq 0 ] && [[ "$trimmed_line" == \`\`\`* ]]; then
      in_fence=1
      language="${trimmed_line:3}"
      language="${language%%[[:space:]]*}"
      fence_number=$((fence_number + 1))
      fence_file="$TEST_ROOT/markdown-fence-$fence_number"
      : >"$fence_file"
    elif [ "$in_fence" -eq 1 ] && [ "$trimmed_line" = '```' ]; then
      if [ "$language" = bash ] || [ "$language" = sh ]; then
        if ! bash -n "$fence_file"; then
          echo "FAIL: shell syntax is invalid in Markdown fence $fence_number of $markdown" >&2
          exit 1
        fi
        first_line="$(awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }' "$fence_file")"
        if [ "$first_line" = '(' ]; then
          second_line="$(awk 'NF { count++; if (count == 2) { gsub(/[[:space:]]+/, " "); print; exit } }' "$fence_file")"
          if [ "$second_line" != 'set -euo pipefail' ]; then
            echo "FAIL: subshell in Markdown fence $fence_number is not strict" >&2
            exit 1
          fi
        fi
        if grep -Fq '. infra/.local/tes-151.env' "$fence_file"; then
          last_line="$(awk 'NF { line = $0 } END { gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); print line }' "$fence_file")"
          if [ "$first_line" != '(' ] || [ "$last_line" != ')' ]; then
            echo "FAIL: config-loading fence $fence_number is not contained in a subshell" >&2
            exit 1
          fi
        fi
      fi
      in_fence=0
      language=""
      fence_file=""
    elif [ "$in_fence" -eq 1 ]; then
      printf '%s\n' "$line" >>"$fence_file"
    fi
  done <"$markdown"

  if [ "$in_fence" -ne 0 ]; then
    echo "FAIL: unclosed Markdown fence $fence_number in $markdown" >&2
    exit 1
  fi
}

find_markdown_fence() {
  local pattern="$1"
  local fence_file
  for fence_file in "$TEST_ROOT"/markdown-fence-*; do
    [ -f "$fence_file" ] || continue
    if grep -Fq -- "$pattern" "$fence_file"; then
      printf '%s\n' "$fence_file"
      return 0
    fi
  done
  return 1
}

expect_markdown_relative_links_exist() {
  local markdown="$1"
  local base_directory
  local match
  local target
  base_directory="$(dirname "$markdown")"

  while IFS= read -r match; do
    target="${match#](}"
    target="${target%)}"
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
    esac
    target="${target%%#*}"
    if [ ! -e "$base_directory/$target" ]; then
      echo "FAIL: missing relative Markdown link target in $markdown: $target" >&2
      exit 1
    fi
  done < <(grep -oE '\]\([^)]*\)' "$markdown")
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
expect_file_contains "$K3S_DIR/install-game.sh" '/dev/tty'
expect_file_contains "$K3S_DIR/install-game.sh" 'read[[:space:]]+-r[[:space:]]+-s[[:space:]]+K3S_TOKEN[[:space:]]*</dev/tty'
expect_file_contains "$K3S_DIR/install-game.sh" 'no controlling TTY is available'
expect_file_contains "$K3S_DIR/install-game.sh" 'K3S_TOKEN may be supplied for existing automation'
expect_file_contains "$K3S_DIR/install-game.sh" 'if[[:space:]]+\[[[:space:]]+-z[[:space:]]+"\$\{K3S_TOKEN:-\}"[[:space:]]+\];[[:space:]]*then'
expect_file_excludes "$K3S_DIR/install-game.sh" 'K3S_TOKEN=<token>'

expect_file_contains "$K3S_DIR/firewall-control.sh" 'API_CLIENT_CIDR'
expect_file_contains "$K3S_DIR/firewall-control.sh" 'CONTROL_API_PORT'
expect_file_contains "$K3S_DIR/firewall-game.sh" 'GAME_PORT'
for firewall_script in "$K3S_DIR/firewall-control.sh" "$K3S_DIR/firewall-game.sh"; do
  expect_file_contains "$firewall_script" 'K3S_POD_CIDR_DEFAULT="10\.42\.0\.0/16"'
  expect_file_contains "$firewall_script" 'K3S_SERVICE_CIDR_DEFAULT="10\.43\.0\.0/16"'
  expect_file_contains "$firewall_script" 'ufw allow from "\$K3S_POD_CIDR_DEFAULT" to any'
  expect_file_contains "$firewall_script" 'ufw allow from "\$K3S_SERVICE_CIDR_DEFAULT" to any'
done
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
expect_file_contains "$VERIFY_SCRIPT" 'auth can-i.*\|\| true'
expect_file_excludes "$VERIFY_SCRIPT" 'POSTGRES_PASSWORD.*echo|echo.*POSTGRES_PASSWORD'

RUNBOOK="$SCRIPT_DIR/README.md"
EVIDENCE="$REPO_ROOT/infra/evidence/tes-152-clean-clone-quickstart.md"
ROOT_README="$REPO_ROOT/README.md"
INFRA_README="$REPO_ROOT/infra/README.md"

expect_file_exists "$RUNBOOK"
expect_file_exists "$EVIDENCE"
expect_file_exists "$ROOT_README"
expect_file_exists "$INFRA_README"

expect_file_contains "$RUNBOOK" 'Ubuntu 24\.04'
expect_file_contains "$RUNBOOK" 'clean (clone|checkout)'
expect_file_contains "$RUNBOOK" 'operator-owned'
expect_file_contains "$RUNBOOK" 'MINECRAFT_EULA=TRUE'
expect_file_contains "$RUNBOOK" '\| `control-1` \|.*K3s server'
expect_file_contains "$RUNBOOK" '\| `control-1` \|.*PostgreSQL'
expect_file_contains "$RUNBOOK" '\| `control-1` \|.*`cloud-control`'
expect_file_contains "$RUNBOOK" 'game-1.*K3s agent.*pinned Paper'
expect_file_contains "$RUNBOOK" 'pinned K3s'
expect_file_contains "$RUNBOOK" 'reset-host\.sh'
expect_file_contains "$RUNBOOK" 'prepare-host\.sh'
expect_file_contains "$RUNBOOK" 'deploy\.sh'
expect_file_contains "$RUNBOOK" 'verify\.sh'
expect_file_contains "$RUNBOOK" 'non-destructive reapply|reapply.*(without deleting|preserv|unchanged)'
expect_file_contains "$RUNBOOK" '2 GiB.*heap'
expect_file_contains "$RUNBOOK" '3 GiB.*container'
expect_file_contains "$RUNBOOK" '10 GiB.*(storage|PVC)'
expect_file_contains "$RUNBOOK" 'host reserve|GAME_HOST_RESERVED'
expect_file_contains "$RUNBOOK" 'direct.*TCP'
expect_file_contains "$RUNBOOK" 'GAME_NODE_ADDRESS'
expect_file_contains "$RUNBOOK" 'GAME_CLUSTER_SOURCE_ADDRESS'
expect_file_contains "$RUNBOOK" 'GAME_DIRECT_ADDRESS'
expect_file_contains "$RUNBOOK" 'Troubleshooting'
expect_file_contains "$RUNBOOK" 'TES-152'
expect_file_contains "$RUNBOOK" 'F2/F3'
expect_file_contains "$RUNBOOK" 'TES-148'
expect_file_contains_fixed "$RUNBOOK" 'git rev-parse --verify --quiet "$VERIFIED_COMMIT^{commit}"'
expect_file_contains_fixed "$RUNBOOK" 'git checkout --detach "$VERIFIED_COMMIT"'
expect_file_excludes "$RUNBOOK" 'git checkout[[:space:]]+<verified-commit>'
expect_file_contains_fixed "$RUNBOOK" '`10.42.0.0/16`'
expect_file_contains_fixed "$RUNBOOK" '`10.43.0.0/16`'
expect_file_contains "$RUNBOOK" '\[control firewall script\]\(\.\./k3s/firewall-control\.sh\)'
expect_file_contains "$RUNBOOK" '\[game firewall script\]\(\.\./k3s/firewall-game\.sh\)'
expect_file_contains_fixed "$RUNBOOK" '/dev/tty'
expect_file_excludes "$RUNBOOK" 'K3S_TOKEN="\$K3S_TOKEN"'
expect_file_excludes "$RUNBOOK" '^[[:space:]]*![[:space:]]+nc[[:space:]]'
negative_probe_prefix='if[[:space:]]+nc[[:space:]]+-vz[[:space:]]+-w[[:space:]]+3[[:space:]]+.*[[:space:]]+'
expect_if_block_contains "$RUNBOOK" "${negative_probe_prefix}5432;[[:space:]]*then" 'exit[[:space:]]+1'
expect_if_block_contains "$RUNBOOK" "${negative_probe_prefix}6443;[[:space:]]*then" 'exit[[:space:]]+1'
expect_markdown_fences_valid "$RUNBOOK"
expect_markdown_relative_links_exist "$RUNBOOK"

expect_file_contains "$EVIDENCE" 'bash infra/two-host/test\.sh'
expect_file_contains "$EVIDENCE" 'bash -n'
expect_file_contains "$EVIDENCE" 'npm run check'
expect_file_contains "$EVIDENCE" 'python3 benchmarks/minecraft/summarize\.py --self-test'
expect_file_contains "$EVIDENCE" 'No live reinstall'
expect_file_contains "$EVIDENCE" 'TES-151 live installation evidence'
expect_file_contains "$EVIDENCE" 'without replacing'
expect_file_contains "$EVIDENCE" 'No secrets.*host addresses'
expect_file_contains "$EVIDENCE" 'ignored local paths'
expect_file_contains "$EVIDENCE" 'without Linear access'
expect_file_contains "$EVIDENCE" '\[TES-151 live installation evidence\]\(tes-151-two-host-installation\.md\)'

expect_file_contains "$ROOT_README" '\]\(infra/two-host/README\.md\)'
expect_file_contains "$ROOT_README" '[Cc]anonical F1 guide'
expect_file_contains "$INFRA_README" '\]\(two-host/README\.md\)'
expect_file_contains "$INFRA_README" 'canonical F1 installation'

expect_markdown_relative_links_exist "$EVIDENCE"
expect_markdown_relative_links_exist "$ROOT_README"
expect_markdown_relative_links_exist "$INFRA_README"

operator_probe_fence="$(find_markdown_fence "Game direct address:")" || {
  echo "FAIL: operator probe fence not found" >&2
  exit 1
}
probe_bin="$TEST_ROOT/probe-bin"
mkdir "$probe_bin"
cat >"$probe_bin/nc" <<'EOF'
#!/usr/bin/env bash
port="${!#}"
case ",${NC_OPEN_PORTS:-}," in
  *",$port,"*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat >"$probe_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit "${CURL_STATUS:-0}"
EOF
cat >"$probe_bin/sudo" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  infra/two-host/deploy.sh) exit "${DEPLOY_STATUS:-0}" ;;
  infra/two-host/verify.sh) exit "${VERIFY_STATUS:-0}" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$probe_bin/nc" "$probe_bin/curl" "$probe_bin/sudo"
printf '%s\n' 198.51.100.20 25565 3000 192.0.2.10 >"$TEST_ROOT/probe-input"

expect_failure "failed direct game probe" \
  env PATH="$probe_bin:$PATH" NC_OPEN_PORTS= CURL_STATUS=0 \
  bash "$operator_probe_fence" <"$TEST_ROOT/probe-input"
expect_failure "failed control health probe" \
  env PATH="$probe_bin:$PATH" NC_OPEN_PORTS=25565 CURL_STATUS=1 \
  bash "$operator_probe_fence" <"$TEST_ROOT/probe-input"
expect_failure "exposed PostgreSQL probe" \
  env PATH="$probe_bin:$PATH" NC_OPEN_PORTS=25565,5432 CURL_STATUS=0 \
  bash "$operator_probe_fence" <"$TEST_ROOT/probe-input"
if ! env PATH="$probe_bin:$PATH" NC_OPEN_PORTS=25565 CURL_STATUS=0 \
  bash "$operator_probe_fence" <"$TEST_ROOT/probe-input" \
  >"$TEST_ROOT/probe.stdout" 2>"$TEST_ROOT/probe.stderr"; then
  echo "FAIL: valid operator probes failed" >&2
  exit 1
fi

deploy_fence_count=0
for fence_file in "$TEST_ROOT"/markdown-fence-*; do
  if grep -Fq 'sudo infra/two-host/deploy.sh' "$fence_file" &&
    grep -Fq 'sudo infra/two-host/verify.sh' "$fence_file"; then
    deploy_fence_count=$((deploy_fence_count + 1))
    expect_failure "deploy failure hidden by successful verify in fence $deploy_fence_count" \
      env PATH="$probe_bin:$PATH" DEPLOY_STATUS=1 VERIFY_STATUS=0 \
      bash "$fence_file"
  fi
done
if [ "$deploy_fence_count" -ne 2 ]; then
  echo "FAIL: expected two deploy/verify fences, found $deploy_fence_count" >&2
  exit 1
fi

echo "two-host tests passed"
