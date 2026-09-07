#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 2 ]; then
  two_host_error "usage: reset-host.sh <control|game> <config-file>"
  exit 1
fi

role="$1"
case "$role" in
  control | game) ;;
  *)
    two_host_error "role must be control or game"
    exit 1
    ;;
esac

load_two_host_config "$2"

if [ "$(id -u)" -ne 0 ]; then
  two_host_error "run reset-host.sh as root"
  exit 1
fi

if [ "$role" = control ]; then
  data_path="$POSTGRES_DATA_PATH"
  if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
    unrelated="$(
      k3s kubectl get pod,deployment,statefulset,daemonset,job,cronjob -A --no-headers 2>/dev/null |
        awk '$1 != "kube-system" && $1 != "cloud-system" && $1 != "cloud-minecraft-paper" {print}'
    )"
    if [ -n "$unrelated" ]; then
      printf '%s\n' "Refusing reset because unrelated workloads exist:" "$unrelated" >&2
      exit 1
    fi
    /usr/local/bin/k3s-uninstall.sh
  fi
else
  data_path="$GAME_DATA_PATH"
  if [ -x /usr/local/bin/k3s-agent-uninstall.sh ]; then
    /usr/local/bin/k3s-agent-uninstall.sh
  fi
fi

validate_data_path data_path
if [ -d "$data_path" ]; then
  find "$data_path" -mindepth 1 -delete
fi

echo "$role host reset completed; only K3s state and the validated TES-151 data path were cleared"
