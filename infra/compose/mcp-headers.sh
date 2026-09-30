#!/usr/bin/env bash
# Prints the MCP Authorization header from .env for clients that run a headers
# helper (Claude Code headersHelper), so the token never lives in the MCP config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CLOUD_COMPOSE_ENV:-$SCRIPT_DIR/../../.env}"

token="$(sed -n 's/^CLOUD_MACHINE_TOKEN=//p' "$ENV_FILE" | tail -n 1)"
printf '{"Authorization":"Bearer %s"}\n' "$token"
