#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 1 ]; then
  two_host_error "usage: verify.sh <config-file>"
  exit 1
fi

load_two_host_config "$1" public

if [ "$(id -u)" -ne 0 ]; then
  two_host_error "run verify.sh as root on control-1"
  exit 1
fi

CONTROL_NODE_NAME="$CONTROL_NODE_NAME" GAME_NODE_NAME="$GAME_NODE_NAME" \
  "$SCRIPT_DIR/../k3s/verify.sh"

k3s kubectl rollout status statefulset/cloud-postgres -n cloud-system --timeout=60s
k3s kubectl rollout status deployment/cloud-control -n cloud-system --timeout=60s
k3s kubectl rollout status deployment/paper-e0-oracle -n cloud-minecraft-paper --timeout=60s

control_pod_node="$(k3s kubectl get pod -n cloud-system -l app=cloud-control -o jsonpath='{.items[0].spec.nodeName}')"
postgres_pod_node="$(k3s kubectl get pod -n cloud-system -l app=cloud-postgres -o jsonpath='{.items[0].spec.nodeName}')"
game_pod_node="$(k3s kubectl get pod -n cloud-minecraft-paper -l app=paper-e0-oracle -o jsonpath='{.items[0].spec.nodeName}')"
if [ "$control_pod_node" != "$CONTROL_NODE_NAME" ] ||
  [ "$postgres_pod_node" != "$CONTROL_NODE_NAME" ] ||
  [ "$game_pod_node" != "$GAME_NODE_NAME" ]; then
  two_host_error "one or more workloads are placed on the wrong host role"
  exit 1
fi

game_node_address="$(k3s kubectl get "node/$GAME_NODE_NAME" -o jsonpath="{.status.addresses[?(@.type=='InternalIP')].address}")"
if [ "$game_node_address" != "$GAME_NODE_ADDRESS" ]; then
  two_host_error "game node InternalIP differs from GAME_NODE_ADDRESS"
  exit 1
fi

service_type="$(k3s kubectl get service/cloud-postgres -n cloud-system -o jsonpath='{.spec.type}')"
if [ "$service_type" != ClusterIP ]; then
  two_host_error "cloud-postgres must remain ClusterIP-only"
  exit 1
fi
if [ -n "$(k3s kubectl get service/cloud-postgres -n cloud-system -o jsonpath='{.spec.ports[*].nodePort}')" ]; then
  two_host_error "cloud-postgres unexpectedly has a node port"
  exit 1
fi
if ss -ltnH '( sport = :5432 )' | grep -q .; then
  two_host_error "the PostgreSQL port is listening on the control host"
  exit 1
fi

for service_account in cloud-control cloud-postgres; do
  can_admin="$(k3s kubectl auth can-i '*' '*' --as="system:serviceaccount:cloud-system:$service_account")"
  if [ "$can_admin" != no ]; then
    two_host_error "$service_account has unexpected cluster-wide access"
    exit 1
  fi
done

k3s kubectl exec -n cloud-system deployment/cloud-control -- \
  node -e 'if (!process.env.CLOUD_MACHINE_TOKEN || process.env.CLOUD_MACHINE_TOKEN.length < 20) process.exit(1)'
k3s kubectl exec -n cloud-system statefulset/cloud-postgres -- pg_isready -U cloud -d cloud >/dev/null

for claim in cloud-system/cloud-postgres-data cloud-minecraft-paper/paper-e0-oracle-data; do
  namespace="${claim%/*}"
  name="${claim#*/}"
  if [ "$(k3s kubectl get "pvc/$name" -n "$namespace" -o jsonpath='{.status.phase}')" != Bound ]; then
    two_host_error "$claim is not bound"
    exit 1
  fi
done
for volume in cloud-postgres-data cloud-paper-data; do
  if [ "$(k3s kubectl get "pv/$volume" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')" != Retain ]; then
    two_host_error "$volume does not use Retain"
    exit 1
  fi
done

paper_cpu="$(k3s kubectl get deployment/paper-e0-oracle -n cloud-minecraft-paper -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')"
paper_memory="$(k3s kubectl get deployment/paper-e0-oracle -n cloud-minecraft-paper -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')"
paper_host_port="$(k3s kubectl get deployment/paper-e0-oracle -n cloud-minecraft-paper -o jsonpath='{.spec.template.spec.containers[0].ports[0].hostPort}')"
if [ "$paper_cpu" != "$GAME_CPU" ] || [ "$paper_memory" != "$GAME_MEMORY" ] || [ "$paper_host_port" != "$GAME_PORT" ]; then
  two_host_error "Paper resources or game port differ from configuration"
  exit 1
fi

node_cpu="$(k3s kubectl get "node/$GAME_NODE_NAME" -o jsonpath='{.status.capacity.cpu}')"
if ((node_cpu < GAME_CPU + GAME_HOST_RESERVED_CPU)); then
  two_host_error "game node CPU is below workload plus GAME_HOST_RESERVED_CPU"
  exit 1
fi

curl -fsS "http://127.0.0.1:$CONTROL_API_PORT/healthz" >/dev/null
timeout 5 bash -c "</dev/tcp/$GAME_DIRECT_ADDRESS/$GAME_PORT"

printf '%s\n' \
  "workload placement verified: control services=control game=game" \
  "game node address verified against the configured local interface" \
  "cloud-postgres exposure verified: ClusterIP only" \
  "machine-token input verified without reading its value" \
  "Paper runtime: cpu=$GAME_CPU heap=$GAME_JAVA_HEAP memory=$GAME_MEMORY" \
  "Paper storage budget: ${GAME_STORAGE_GIB}Gi (PVC request, not a filesystem quota)" \
  "game host reserve: cpu=$GAME_HOST_RESERVED_CPU memory=${GAME_HOST_RESERVED_MEMORY_GIB}Gi disk=${GAME_HOST_RESERVED_DISK_GIB}Gi" \
  "direct game path verified: configured worker address and TCP port"
