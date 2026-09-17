#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
PAPER_DIR="$REPOSITORY_ROOT/catalog/games/minecraft-java/paper/k8s"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 2 ]; then
  two_host_error "usage: render.sh <config-file> <empty-output-directory>"
  exit 1
fi

config_file="$1"
output_dir="$2"
load_two_host_config "$config_file" public

if [ ! -d "$output_dir" ]; then
  two_host_error "output directory must already exist"
  exit 1
fi
if find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  two_host_error "output directory must be empty"
  exit 1
fi

render_common_template() {
  local source_file="$1"
  local destination_file="$2"
  sed \
    -e "s|@CONTROL_NODE_NAME@|$CONTROL_NODE_NAME|g" \
    -e "s|@GAME_NODE_NAME@|$GAME_NODE_NAME|g" \
    -e "s|@CONTROL_API_PORT@|$CONTROL_API_PORT|g" \
    -e "s|@POSTGRES_DATA_PATH@|$POSTGRES_DATA_PATH|g" \
    -e "s|@GAME_DATA_PATH@|$GAME_DATA_PATH|g" \
    -e "s|@POSTGRES_STORAGE_GIB@|$POSTGRES_STORAGE_GIB|g" \
    -e "s|@GAME_STORAGE_GIB@|$GAME_STORAGE_GIB|g" \
    "$source_file" >"$destination_file"
}

render_common_template \
  "$TEMPLATE_DIR/control.yaml.template" \
  "$output_dir/10-control.yaml"
render_common_template \
  "$TEMPLATE_DIR/game-storage.yaml.template" \
  "$output_dir/20-game-storage.yaml"

{
  sed -n '1,$p' "$PAPER_DIR/namespace.yaml"
  printf '%s\n' '---'
  sed -n '1,$p' "$PAPER_DIR/serviceaccount.yaml"
  printf '%s\n' '---'
  sed \
    -e "s|value: \"TRUE\"|value: \"$MINECRAFT_EULA\"|" \
    -e "s|value: 2G|value: $GAME_JAVA_HEAP|" \
    -e "s|value: \"-XX:ActiveProcessorCount=2\"|value: \"-XX:ActiveProcessorCount=$GAME_CPU\"|" \
    -e "s|hostPort: 25565|hostPort: $GAME_PORT|" \
    -e "s|cpu: \"2\"|cpu: \"$GAME_CPU\"|g" \
    -e "s|memory: 3Gi|memory: $GAME_MEMORY|g" \
    "$PAPER_DIR/deployment.yaml"
} >"$output_dir/30-game.yaml"

cp "$TEMPLATE_DIR/control-rbac.yaml" "$output_dir/40-control-rbac.yaml"
cp "$PAPER_DIR/storageclass.yaml" "$output_dir/50-managed-storage.yaml"

if grep -R '@[A-Z_][A-Z_]*@' "$output_dir" >/dev/null; then
  two_host_error "rendered manifests contain unresolved placeholders"
  exit 1
fi

echo "Rendered manifests in $output_dir"
