# TES-76 MCP tools evidence

Date: 2026-09-19

Branch: `agustinpedernera147/tes-76-f313-expose-the-four-mcp-tools-against-control-1`

Base: `cc41f85` (`origin/main` when work began)

Implementation commit:

- `f03b7df` serves `POST /mcp` (MCP Streamable HTTP, stateless JSON mode)
  behind the machine token and exposes `minecraft_create`, `minecraft_start`,
  `minecraft_stop` and `minecraft_status` over the existing durable
  `ControlStore.mutate` and status code. No new dependency.

## Verification

`npm run check`

- TypeScript build passed.
- 21 compiled unit tests passed; 0 failed, skipped, or cancelled. Four new
  tests cover initialize, tool listing, the full tool flow, error mapping,
  authentication and JSON-RPC errors.

`TEST_DATABASE_URL='<disposable PostgreSQL URL>' npm run test:integration`

- PostgreSQL 17.6 ran in a temporary local Docker container.
- 25 integration tests passed; 0 failed, skipped, or cancelled.
- The temporary container was removed after the run.

`python3 benchmarks/minecraft/summarize.py --self-test` passed and
`benchmarks/minecraft/` is unchanged. `bash infra/compose/test.sh` passed.

## Real Compose run

Host: macOS 26.5 arm64, Docker Engine 28.4.0, Compose 2.39.4. Previous named
volumes removed with `destroy.sh --yes`; `cloud-control` image rebuilt from
this branch; `.env` local and not committed.

The agent was a Node script using the official MCP TypeScript SDK client
(`@modelcontextprotocol/sdk` 1.30.0, `StreamableHTTPClientTransport`) with only
the control URL and bearer token. It was installed outside the repository.

| Step | Result |
| --- | --- |
| `setup.sh` | Ready in 7 s; `game-1` created stopped. |
| Connect with a wrong token | Rejected with HTTP `401 unauthorized`. |
| Initialize and `tools/list` | `cloud-control`; the four `minecraft_*` tools. |
| `minecraft_create` without EULA | `isError`, `action_required: accept_eula`. |
| `minecraft_create` | `queued` with durable `request_id`, `server_id` and `status_url`. |
| Create replay, same key | Original response. |
| Distinct second create | `isError`, `capacity_unavailable`. |
| `minecraft_status` polling | `queued`, `provisioning` while the container healthcheck was `starting`; `running` with endpoint `127.0.0.1:25565` after 33 s, once the healthcheck was `healthy`. No status carried an endpoint before `running`. A marker file was written to `/data`. |
| `minecraft_stop` | `stopping`; replay returned the original response. |
| Same key, `minecraft_start` | `isError`, `idempotency_key_reused`. |
| Stop completion | `stopped` after 2 s; container exit code 0, not OOM-killed. |
| `minecraft_start` | `queued`, then `running` 22 s later. |
| World and endpoint | Same marker in `/data`, same `127.0.0.1:25565` endpoint. |
| Credential boundary | The game container mounts only `cloud_game-world:/data`; the agent received no Docker or host credentials. |
| `shutdown.sh` | Stack stopped; game exit code 0; named volumes preserved. |

`setup.sh` runs `docker compose up` without `--build`, so an existing
`cloud-control` image is reused after a code change. The run above rebuilt the
image first with `docker compose build cloud-control`.

No credentials, host addresses, or operator identifiers are included here.
