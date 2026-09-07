#!/usr/bin/env bash
# Installs the K3s server on control-1 (TES-59).
# Run directly on control-1 with sudo. Takes no operational identifiers as
# arguments or literals — nothing here is specific to any one host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../two-host/lib.sh
source "$SCRIPT_DIR/../two-host/lib.sh"

K3S_VERSION="${K3S_VERSION:-v1.36.4+k3s1}"
NODE_NAME="${NODE_NAME:-control-1}"
CONTROL_PRIVATE_ADDRESS="${CONTROL_PRIVATE_ADDRESS:?Set CONTROL_PRIVATE_ADDRESS to control-1's private IPv4 address}"
NODE_TAINT="${NODE_TAINT:-cloud.example/role=control:NoSchedule}"
NODE_LABEL="${NODE_LABEL:-cloud.example/role=control}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

validate_node_name NODE_NAME
validate_ipv4 CONTROL_PRIVATE_ADDRESS
if ! [[ "$K3S_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]]; then
  two_host_error "K3S_VERSION must be an exact vX.Y.Z+k3sN version"
  exit 1
fi

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_EXEC="server \
    --flannel-backend=wireguard-native \
    --disable=traefik,servicelb \
    --node-name=${NODE_NAME} \
    --node-ip=${CONTROL_PRIVATE_ADDRESS} \
    --advertise-address=${CONTROL_PRIVATE_ADDRESS} \
    --tls-san=${CONTROL_PRIVATE_ADDRESS} \
    --node-label=${NODE_LABEL} \
    --node-taint=${NODE_TAINT} \
    --write-kubeconfig-mode=600" \
  sh -

echo
echo "K3s server installed. Resolved version:"
/usr/local/bin/k3s --version

echo
echo "Join token is available at /var/lib/rancher/k3s/server/node-token. Read it out-of-band; do not capture it in setup logs."

echo
echo "Next: run firewall-control.sh <GAME-1-IP> here, then install-game.sh on game-1."
