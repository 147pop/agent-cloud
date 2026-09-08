#!/usr/bin/env bash
# Installs the K3s agent on game-1 and labels it as the game worker (TES-59).
# Run directly on game-1 with sudo.
#
# Required env vars (K3S_TOKEN may be supplied for existing automation):
#   K3S_URL   = https://<control-1-ip>:6443
#   K3S_TOKEN = token printed by install-control.sh
# If K3S_TOKEN is not set, this script prompts on /dev/tty after sudo has
# started. A non-interactive caller must provide K3S_TOKEN through its env.
#
# Example:
#   K3S_URL=https://<control-ip>:6443 K3S_TOKEN=<token> ./install-game.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../two-host/lib.sh
source "$SCRIPT_DIR/../two-host/lib.sh"

: "${K3S_URL:?Set K3S_URL=https://<control-1-ip>:6443}"
: "${GAME_NODE_ADDRESS:?Set GAME_NODE_ADDRESS to an IPv4 address assigned to game-1}"

K3S_VERSION="${K3S_VERSION:-v1.36.4+k3s1}"
NODE_NAME="${NODE_NAME:-game-1}"
NODE_LABEL="${NODE_LABEL:-cloud.example/role=game}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if [ -z "${K3S_TOKEN:-}" ]; then
  if ! { [ -c /dev/tty ] && : </dev/tty; }; then
    echo "K3S_TOKEN is unset and no controlling TTY is available at /dev/tty; set K3S_TOKEN for non-interactive automation or run sudo from a terminal." >&2
    exit 1
  fi
  printf 'K3s join token: ' >/dev/tty
  if ! IFS= read -r -s K3S_TOKEN </dev/tty; then
    printf '\n' >/dev/tty
    echo "Unable to read K3S_TOKEN from /dev/tty; set K3S_TOKEN for non-interactive automation." >&2
    exit 1
  fi
  printf '\n' >/dev/tty
fi

: "${K3S_TOKEN:?Set K3S_TOKEN or run sudo from a terminal so the script can prompt on /dev/tty}"

validate_node_name NODE_NAME
validate_ipv4 GAME_NODE_ADDRESS
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
    --node-ip=${GAME_NODE_ADDRESS} \
    --node-label=${NODE_LABEL}" \
  sh -

echo
echo "K3s agent installed and labeled ${NODE_LABEL}."
echo "Next: run firewall-game.sh <CONTROL-1-IP> here, then verify.sh from control-1."
