#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

for script in "$SCRIPT_DIR"/*.sh; do
  bash -n "$script"
done

node --check "$SCRIPT_DIR/protocol-status.mjs"

# The agent MCP config and its headers helper must produce valid JSON.
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$REPOSITORY_ROOT/.mcp.json"
CLOUD_COMPOSE_ENV="$SCRIPT_DIR/config.example.env" bash "$SCRIPT_DIR/mcp-headers.sh" |
  node -e 'const h = JSON.parse(require("fs").readFileSync(0, "utf8")); if (!/^Bearer .{20,}/.test(h.Authorization)) process.exit(1)'

docker compose --env-file "$SCRIPT_DIR/config.example.env" -f "$REPOSITORY_ROOT/compose.yaml" config --quiet
printf '%s\n' 'Compose package checks passed'
