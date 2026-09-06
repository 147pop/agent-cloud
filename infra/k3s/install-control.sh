#!/usr/bin/env bash
# Installs the K3s server on control-1 (TES-59).
# Run directly on control-1 with sudo. Takes no operational identifiers as
# arguments or literals — nothing here is specific to any one host.
set -euo pipefail

K3S_CHANNEL="${K3S_CHANNEL:-stable}"
NODE_TAINT="${NODE_TAINT:-cloud.example/role=control:NoSchedule}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_CHANNEL="$K3S_CHANNEL" \
  INSTALL_K3S_EXEC="server \
    --flannel-backend=wireguard-native \
    --disable=traefik,servicelb \
    --node-taint=${NODE_TAINT} \
    --write-kubeconfig-mode=600" \
  sh -

echo
echo "K3s server installed. Resolved version:"
/usr/local/bin/k3s --version

echo
echo "Join token for game-1 (copy it out-of-band, e.g. into the TES-53 archive; do not commit it):"
cat /var/lib/rancher/k3s/server/node-token

echo
echo "Next: run firewall-control.sh <GAME-1-IP> here, then install-game.sh on game-1."
