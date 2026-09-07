#!/usr/bin/env bash
# Installs the K3s agent on game-1 and labels it as the game worker (TES-59).
# Run directly on game-1 with sudo.
#
# Required env vars (pass at invocation, never commit them):
#   K3S_URL   = https://<control-1-ip>:6443
#   K3S_TOKEN = token printed by install-control.sh
#
# Example:
#   K3S_URL=https://<control-ip>:6443 K3S_TOKEN=<token> ./install-game.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../two-host/lib.sh
source "$SCRIPT_DIR/../two-host/lib.sh"

: "${K3S_URL:?Set K3S_URL=https://<control-1-ip>:6443}"
: "${K3S_TOKEN:?Set K3S_TOKEN=<token from install-control.sh>}"
: "${GAME_PRIVATE_ADDRESS:?Set GAME_PRIVATE_ADDRESS to game-1's private IPv4 address}"

K3S_VERSION="${K3S_VERSION:-v1.36.4+k3s1}"
NODE_NAME="${NODE_NAME:-game-1}"
NODE_LABEL="${NODE_LABEL:-cloud.example/role=game}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

validate_node_name NODE_NAME
validate_ipv4 GAME_PRIVATE_ADDRESS
if ! [[ "$K3S_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]]; then
  two_host_error "K3S_VERSION must be an exact vX.Y.Z+k3sN version"
  exit 1
fi

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_URL="$K3S_URL" \
  K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="agent \
    --node-name=${NODE_NAME} \
    --node-ip=${GAME_PRIVATE_ADDRESS} \
    --node-label=${NODE_LABEL}" \
  sh -

echo
echo "K3s agent installed and labeled ${NODE_LABEL}."
echo "Next: run firewall-game.sh <CONTROL-1-IP> here, then verify.sh from control-1."
