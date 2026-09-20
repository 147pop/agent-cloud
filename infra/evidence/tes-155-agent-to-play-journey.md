# TES-155 automated agent-to-play journey evidence

Date: 2026-09-20

Branch: `agustinpedernera147/tes-155-f41-automate-the-single-host-compose-agent-to-play-journey`

Base: `8bbb509` (`origin/main` when work began)

Implementation commit:

- `3a44ffc` adds `infra/compose/journey.sh` and
  `infra/compose/protocol-status.mjs` (a dependency-free Minecraft status
  ping), extends `infra/compose/test.sh` with a syntax check for the client
  and documents the journey in `infra/compose/README.md`.

## Verification

`npm run check`

- TypeScript build passed.
- 25 compiled unit tests passed; 0 failed, skipped, or cancelled.

`bash infra/compose/test.sh`: passed (adds `node --check` for the protocol
client).

`python3 benchmarks/minecraft/summarize.py --self-test`: passed;
`benchmarks/minecraft/` is unchanged.

## Real Compose run

Host: macOS 26.5 arm64, Docker Engine 28.4.0, Compose 2.39.4-desktop.1.
Executed `bash infra/compose/journey.sh --accept-eula --fresh --clone
/tmp/cloud-journey`: the script cloned the branch checkout to a fresh tree,
generated a random local `.env` (never printed), destroyed the previous
named volumes, ran `npm ci`, `npm run build`, `docker compose build
cloud-control` and `setup.sh` inside the clone, then exercised the journey.
Total duration 89 s. Every step is asserted by the script; it exits non-zero
on the first failure.

| Step | Result |
| --- | --- |
| Preflight, clean state, generated configuration | Pass; previous volumes destroyed via `destroy.sh --yes`. |
| `setup.sh` inside the clean clone | `game-1` created stopped, `cloud-control` started. |
| Control API readiness | `/healthz` after 1 s. |
| REST create without EULA acceptance | `409 {"error":"action_required","action_required":"accept_eula"}`. |
| REST create one (EULA accepted) | `202`; server and request IDs returned. |
| Status until running | `running` after 46 s; endpoint `127.0.0.1:25565`. |
| Minecraft protocol ping | `Paper 26.2`, protocol 776, 0/2 players, 12 ms latency. |
| MCP `initialize` and `tools/list` | `cloud-control` server info; the four `minecraft_*` tools. |
| MCP `minecraft_status` | `running` with the same endpoint as REST. |
| CLI `status` | `running`, same endpoint. |
| CLI `create` without `--accept-eula` | Exit 1; `action_required: accept_eula` on stderr. |
| World marker | Marker written and read back in `/data`. |
| MCP `minecraft_stop` | `stopped` after 2 s. |
| Protocol ping while stopped | `status failed: ECONNREFUSED`. |
| CLI `start --wait` | `running` after 22 s; same endpoint; marker preserved. |
| Second create (distinct name and request ID) | `409 {"error":"capacity_unavailable"}`; original server kept its ID, state and endpoint. |
| REST with a wrong token | `401 {"error":"unauthorized"}`. |
| `shutdown.sh` | Stack stopped; `cloud_game-world` and `cloud_postgres-data` preserved. |

The protocol client is host-side and dependency-free; readiness and
reconnection were proven with the Minecraft status protocol, not a full
player login (the server is online-mode).

No credentials, host addresses, or operator identifiers are included here.
