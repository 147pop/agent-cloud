#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 1 ]; then
  two_host_error "usage: deploy.sh <config-file>"
  exit 1
fi

load_two_host_config "$1"

if [ "$(id -u)" -ne 0 ]; then
  two_host_error "run deploy.sh as root on control-1"
  exit 1
fi

command -v k3s >/dev/null
command -v docker >/dev/null

work_dir="$(mktemp -d)"
cleanup() {
  find "$work_dir" -mindepth 1 -delete
  rmdir "$work_dir"
}
trap cleanup EXIT
render_dir="$work_dir/rendered"
secret_file="$work_dir/secrets.env"
mkdir "$render_dir"
umask 077
printf '%s\n' \
  "postgres-password=$POSTGRES_PASSWORD" \
  "machine-token=$CLOUD_MACHINE_TOKEN" >"$secret_file"

"$SCRIPT_DIR/render.sh" "$1" "$render_dir" >/dev/null

k3s kubectl create namespace cloud-system --dry-run=client -o yaml | k3s kubectl apply -f -
k3s kubectl create namespace cloud-minecraft-paper --dry-run=client -o yaml | k3s kubectl apply -f -
k3s kubectl create secret generic cloud-control-secrets \
  --namespace cloud-system \
  --from-env-file="$secret_file" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

docker build \
  --file "$REPOSITORY_ROOT/apps/cloud-control/Dockerfile" \
  --tag cloud-control:tes-151 \
  "$REPOSITORY_ROOT"
docker save cloud-control:tes-151 | k3s ctr images import -

k3s kubectl apply -f "$render_dir/10-control.yaml"
k3s kubectl apply -f "$render_dir/20-game-storage.yaml"
k3s kubectl apply -f "$render_dir/30-game.yaml"
k3s kubectl apply -f "$render_dir/40-control-rbac.yaml"

# The repository commit may produce a new local image under the same private
# tag. Restart only the stateless control process so it uses that import.
k3s kubectl rollout restart deployment/cloud-control -n cloud-system
k3s kubectl rollout status statefulset/cloud-postgres -n cloud-system --timeout=300s
k3s kubectl rollout status deployment/cloud-control -n cloud-system --timeout=300s
k3s kubectl rollout status deployment/paper-e0-oracle -n cloud-minecraft-paper --timeout=600s

echo "TES-151 workloads deployed; durable PVCs and host data paths were not deleted"
