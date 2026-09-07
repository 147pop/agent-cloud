#!/usr/bin/env bash

two_host_error() {
  printf 'two-host: %s\n' "$*" >&2
  return 1
}

require_two_host_value() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    two_host_error "required configuration variable $name is missing"
  fi
}

validate_positive_integer() {
  local name="$1"
  local value="${!name}"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    two_host_error "$name must be a positive integer"
  fi
}

validate_port() {
  local name="$1"
  local value="${!name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || ((value < 1 || value > 65535)); then
    two_host_error "$name must be an integer between 1 and 65535"
  fi
}

validate_ipv4() {
  local name="$1"
  local value="${!name}"
  local first second third fourth octet

  if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    two_host_error "$name must be an IPv4 address"
    return
  fi

  IFS=. read -r first second third fourth <<<"$value"
  for octet in "$first" "$second" "$third" "$fourth"; do
    if ((10#$octet > 255)); then
      two_host_error "$name must be an IPv4 address"
      return
    fi
  done
}

validate_ipv4_cidr() {
  local name="$1"
  local value="${!name}"
  local address prefix

  if [[ "$value" != */* ]]; then
    two_host_error "$name must be an IPv4 CIDR"
    return
  fi

  address="${value%/*}"
  prefix="${value##*/}"
  if ! [[ "$prefix" =~ ^[0-9]+$ ]] || ((prefix < 0 || prefix > 32)); then
    two_host_error "$name must be an IPv4 CIDR"
    return
  fi

  local cidr_address="$address"
  validate_ipv4 cidr_address
}

validate_node_name() {
  local name="$1"
  local value="${!name}"
  if ((${#value} > 63)) ||
    ! [[ "$value" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
    two_host_error "$name must be a lowercase DNS-compatible node name"
  fi
}

validate_memory_value() {
  local name="$1"
  local value="${!name}"
  if ! [[ "$value" =~ ^[1-9][0-9]*(Mi|Gi)$ ]]; then
    two_host_error "$name must use a positive Mi or Gi value"
  fi
}

validate_heap_value() {
  local name="$1"
  local value="${!name}"
  if ! [[ "$value" =~ ^[1-9][0-9]*[MG]$ ]]; then
    two_host_error "$name must use a positive M or G value"
  fi
}

validate_data_path() {
  local name="$1"
  local value="${!name}"
  case "$value" in
    /var/lib/cloud/*) ;;
    *)
      two_host_error "$name must be below /var/lib/cloud/"
      return
      ;;
  esac

  if [[ "$value" == *'/../'* || "$value" == */.. || "$value" == *'/./'* ||
    "$value" == */. || "$value" == *'//'* ]]; then
    two_host_error "$name must be a normalized absolute path"
  fi
}

validate_secret() {
  local name="$1"
  local value="${!name}"
  if ((${#value} < 20)) || [[ "$value" == 'replace-me' ]] ||
    ! [[ "$value" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
    two_host_error "$name must be replaced with an operator-owned value of at least 20 bytes"
  fi
}

load_two_host_config() {
  local config_file="${1:-}"
  local mode="${2:-full}"
  local name
  local -a required=(
    K3S_VERSION
    CONTROL_NODE_NAME
    GAME_NODE_NAME
    CONTROL_PRIVATE_ADDRESS
    GAME_PRIVATE_ADDRESS
    GAME_DIRECT_ADDRESS
    CONTROL_API_CLIENT_CIDR
    CONTROL_API_PORT
    GAME_PORT
    POSTGRES_DATA_PATH
    GAME_DATA_PATH
    POSTGRES_STORAGE_GIB
    GAME_STORAGE_GIB
    GAME_CPU
    GAME_JAVA_HEAP
    GAME_MEMORY
    GAME_HOST_RESERVED_CPU
    GAME_HOST_RESERVED_MEMORY_GIB
    GAME_HOST_RESERVED_DISK_GIB
    MINECRAFT_EULA
  )

  case "$mode" in
    full) required+=(POSTGRES_PASSWORD CLOUD_MACHINE_TOKEN) ;;
    public) ;;
    *)
      two_host_error "configuration mode must be full or public"
      return
      ;;
  esac

  if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
    two_host_error "configuration file does not exist"
    return
  fi

  for name in "${required[@]}"; do
    unset "$name"
  done

  # This is an operator-owned file outside Git. Treat it like a shell script.
  set -a
  # shellcheck disable=SC1090
  source "$config_file"
  set +a

  for name in "${required[@]}"; do
    require_two_host_value "$name" || return
  done

  if ! [[ "$K3S_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]]; then
    two_host_error "K3S_VERSION must be an exact vX.Y.Z+k3sN version"
    return
  fi

  validate_node_name CONTROL_NODE_NAME || return
  validate_node_name GAME_NODE_NAME || return
  validate_ipv4 CONTROL_PRIVATE_ADDRESS || return
  validate_ipv4 GAME_PRIVATE_ADDRESS || return
  validate_ipv4 GAME_DIRECT_ADDRESS || return
  validate_ipv4_cidr CONTROL_API_CLIENT_CIDR || return
  validate_port CONTROL_API_PORT || return
  validate_port GAME_PORT || return
  validate_data_path POSTGRES_DATA_PATH || return
  validate_data_path GAME_DATA_PATH || return
  validate_positive_integer POSTGRES_STORAGE_GIB || return
  validate_positive_integer GAME_STORAGE_GIB || return
  validate_positive_integer GAME_CPU || return
  validate_heap_value GAME_JAVA_HEAP || return
  validate_memory_value GAME_MEMORY || return
  validate_positive_integer GAME_HOST_RESERVED_CPU || return
  validate_positive_integer GAME_HOST_RESERVED_MEMORY_GIB || return
  validate_positive_integer GAME_HOST_RESERVED_DISK_GIB || return

  if [ "$MINECRAFT_EULA" != TRUE ]; then
    two_host_error "MINECRAFT_EULA must be TRUE after explicit operator acceptance"
    return
  fi

  if [ "$mode" = full ]; then
    validate_secret POSTGRES_PASSWORD || return
    validate_secret CLOUD_MACHINE_TOKEN || return
  fi
}
