#!/usr/bin/env bash
# Checks the TES-59 done criteria. Run on control-1 after both install
# scripts and both firewall scripts have run.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
NODE_TAINT_KEY="${NODE_TAINT_KEY:-cloud.example/role}"
GAME_LABEL="${GAME_LABEL:-cloud.example/role=game}"

echo "== Node status (both must be Ready) =="
k3s kubectl get nodes -o wide

echo
echo "== control taint (expect ${NODE_TAINT_KEY}=control:NoSchedule) =="
k3s kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'

echo
echo "== game-1 label (expect ${GAME_LABEL}) =="
k3s kubectl get nodes -l "${GAME_LABEL}" -o name

echo
echo "== schedulability check: nothing without a matching toleration can land on control =="
k3s kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.cloud\.example/role}{"\n"}{end}'
