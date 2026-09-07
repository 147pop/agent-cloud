#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 2 ]; then
  two_host_error "usage: prepare-host.sh <control|game> <config-file>"
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
  two_host_error "run prepare-host.sh as root"
  exit 1
fi

if [ "$role" = control ]; then
  command -v k3s >/dev/null
  command -v docker >/dev/null
  install -d -m 0770 -o 999 -g 999 "$POSTGRES_DATA_PATH"
  echo "control host prepared: PostgreSQL path owner=999:999 mode=0770"
  exit 0
fi

command -v k3s >/dev/null
install -d -m 0770 -o 1000 -g 1000 "$GAME_DATA_PATH"

available_cpu="$(getconf _NPROCESSORS_ONLN)"
required_cpu="$((GAME_CPU + GAME_HOST_RESERVED_CPU))"
if ((available_cpu < required_cpu)); then
  two_host_error "game host CPU capacity is below workload plus configured reserve"
  exit 1
fi

memory_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
case "$GAME_MEMORY" in
  *Gi) game_memory_kib="$((${GAME_MEMORY%Gi} * 1024 * 1024))" ;;
  *Mi) game_memory_kib="$((${GAME_MEMORY%Mi} * 1024))" ;;
esac
required_memory_kib="$((game_memory_kib + GAME_HOST_RESERVED_MEMORY_GIB * 1024 * 1024))"
if ((memory_kib < required_memory_kib)); then
  two_host_error "game host memory is below workload plus configured reserve"
  exit 1
fi

available_disk_kib="$(df -Pk "$GAME_DATA_PATH" | awk 'NR == 2 {print $4}')"
required_disk_kib="$(((GAME_STORAGE_GIB + GAME_HOST_RESERVED_DISK_GIB) * 1024 * 1024))"
if ((available_disk_kib < required_disk_kib)); then
  two_host_error "game host disk is below storage budget plus configured reserve"
  exit 1
fi

printf '%s\n' \
  "game host prepared: Minecraft path owner=1000:1000 mode=0770" \
  "game resource gate: cpu=${GAME_CPU} reserved_cpu=${GAME_HOST_RESERVED_CPU}" \
  "game resource gate: memory=${GAME_MEMORY} reserved_memory_gib=${GAME_HOST_RESERVED_MEMORY_GIB}" \
  "game storage gate: budget_gib=${GAME_STORAGE_GIB} reserved_disk_gib=${GAME_HOST_RESERVED_DISK_GIB}"
