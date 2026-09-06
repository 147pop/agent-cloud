#!/usr/bin/env bash
# Restricts K3s cluster ports on control-1 to game-1 only (TES-25).
# Does not touch existing SSH rules — those are already scoped per TES-53.
# Requires ufw. Run on control-1 with sudo.
set -euo pipefail

GAME_IP="${1:?Usage: firewall-control.sh <game-1-ip>}"

ufw allow from "$GAME_IP" to any port 6443 proto tcp comment "k3s api: game-1"
ufw allow from "$GAME_IP" to any port 51820 proto udp comment "k3s flannel wireguard-native: game-1"

echo "Rules added. Current status:"
ufw status verbose
