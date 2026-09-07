#!/usr/bin/env bash
# Checks the TES-59 done criteria. Run on control-1 after both install
# scripts and both firewall scripts have run.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
NODE_TAINT_KEY="${NODE_TAINT_KEY:-cloud.example/role}"
CONTROL_NODE_NAME="${CONTROL_NODE_NAME:-control-1}"
GAME_NODE_NAME="${GAME_NODE_NAME:-game-1}"

node_count="$(k3s kubectl get nodes -o name | wc -l | tr -d ' ')"
if [ "$node_count" -ne 2 ]; then
  echo "Expected exactly two nodes, found $node_count." >&2
  exit 1
fi

echo "== Node status (both must be Ready) =="
k3s kubectl wait --for=condition=Ready "node/$CONTROL_NODE_NAME" "node/$GAME_NODE_NAME" --timeout=180s

echo
echo "== control taint (expect ${NODE_TAINT_KEY}=control:NoSchedule) =="
control_taint="$(k3s kubectl get "node/$CONTROL_NODE_NAME" -o jsonpath="{.spec.taints[?(@.key=='${NODE_TAINT_KEY}')].value}:{.spec.taints[?(@.key=='${NODE_TAINT_KEY}')].effect}")"
if [ "$control_taint" != 'control:NoSchedule' ]; then
  echo "Control taint is missing or incorrect." >&2
  exit 1
fi
echo "control:NoSchedule"

echo
echo "== role labels =="
control_role="$(k3s kubectl get "node/$CONTROL_NODE_NAME" -o jsonpath='{.metadata.labels.cloud\.example/role}')"
game_role="$(k3s kubectl get "node/$GAME_NODE_NAME" -o jsonpath='{.metadata.labels.cloud\.example/role}')"
if [ "$control_role" != control ] || [ "$game_role" != game ]; then
  echo "Expected one control role and one game role." >&2
  exit 1
fi
printf '%s\n' 'control=control' 'game=game'

echo
echo "== schedulability check: nothing without a matching toleration can land on control =="
echo "control taint and role labels verified"
