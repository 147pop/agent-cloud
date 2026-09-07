#!/usr/bin/env bash
# Restricts K3s cluster ports on game-1 to control-1 only (TES-25).
# The agent dials out to control-1:6443; it doesn't need that port open
# inbound. Only the flannel wireguard-native tunnel needs an inbound rule.
# Does not touch existing SSH rules or the Minecraft hostPort (25565) — the
# latter is intentionally public, that's the Spectrum origin.
# Requires ufw. Run on game-1 with sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../two-host/lib.sh
source "$SCRIPT_DIR/../two-host/lib.sh"

CONTROL_IP="${1:?Usage: firewall-game.sh <control-1-ip> [game-port]}"
GAME_PORT="${2:-25565}"

validate_ipv4 CONTROL_IP
validate_port GAME_PORT

ufw allow from "$CONTROL_IP" to any port 51820 proto udp comment "k3s flannel wireguard-native: control-1"
ufw allow "$GAME_PORT/tcp" comment "minecraft direct foundation path"

echo "Rule added. Current status:"
ufw status verbose
