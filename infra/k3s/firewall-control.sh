#!/usr/bin/env bash
# Restricts K3s cluster ports on control-1 to game-1 only (TES-25).
# Does not touch existing SSH rules — those are already scoped per TES-53.
# Requires ufw. Run on control-1 with sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../two-host/lib.sh
source "$SCRIPT_DIR/../two-host/lib.sh"

GAME_IP="${1:?Usage: firewall-control.sh <game-1-ip> <api-client-cidr> [api-port]}"
API_CLIENT_CIDR="${2:?Usage: firewall-control.sh <game-1-ip> <api-client-cidr> [api-port]}"
CONTROL_API_PORT="${3:-3000}"

validate_ipv4 GAME_IP
validate_ipv4_cidr API_CLIENT_CIDR
validate_port CONTROL_API_PORT

ufw allow from "$GAME_IP" to any port 6443 proto tcp comment "k3s api: game-1"
ufw allow from "$GAME_IP" to any port 51820 proto udp comment "k3s flannel wireguard-native: game-1"
ufw allow from "$API_CLIENT_CIDR" to any port "$CONTROL_API_PORT" proto tcp comment "cloud-control api: operator client"

echo "Rules added. Current status:"
ufw status verbose
