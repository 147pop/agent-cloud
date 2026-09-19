# TES-160 CLI client evidence

Date: 2026-09-19

Branch: `agustinpedernera147/tes-160-f314-expose-the-control-operations-through-a-cli-client`

Base: `6eef20f` (`origin/main` when work began)

Implementation commit:

- `74618aa` adds `apps/cloud-control/src/cli.ts` (`npm run cloud`), a REST
  client for `create`, `start`, `stop` and `status` using the machine token
  from the environment. No new dependency.

## Verification

`npm run check`

- TypeScript build passed.
- 24 compiled unit tests passed; 0 failed, skipped, or cancelled. Three new
  tests cover the full command flow, `--wait`, request-ID replay, control
  errors, usage errors and missing or wrong credentials.

`TEST_DATABASE_URL='<disposable PostgreSQL URL>' npm run test:integration`

- PostgreSQL 17.6 ran in a temporary local Docker container.
- 25 integration tests passed; 0 failed, skipped, or cancelled.
- The temporary container was removed after the run.

`python3 benchmarks/minecraft/summarize.py --self-test` passed and
`benchmarks/minecraft/` is unchanged. `bash infra/compose/test.sh` passed.

## Real Compose run

Host: macOS 26.5 arm64, Docker Engine 28.4.0, Compose 2.39.4. Previous named
volumes removed with `destroy.sh --yes`; `cloud-control` image rebuilt from
this branch; `.env` local and not committed. Every lifecycle call used
`npm run -s cloud`, run on the host with only `CLOUD_MACHINE_TOKEN` exported
from `.env`.

| Step | Result |
| --- | --- |
| `create one` without `--accept-eula` | Exit 1; `action_required: accept_eula` and the EULA hint on stderr. |
| `create one --accept-eula --request-id cli-create-one --wait` | `queued` with request and server IDs, then `running` with endpoint `127.0.0.1:25565` after 35 s. The container healthcheck was `healthy`. A marker file was written to `/data`. |
| Create replay, same ID | Exit 0; original response. |
| `create two`, new ID | Exit 1; `capacity_unavailable`. |
| `stop --wait` | `stopping`, then `stopped` after 2 s; container exit code 0, not OOM-killed. |
| Stop replay, same ID | Exit 0; original response. |
| `start` with the stop ID | Exit 1; `idempotency_key_reused`. |
| `start --wait` | `queued`, then `running` after 22 s with the same endpoint. |
| `status` | `running`, endpoint `127.0.0.1:25565`; marker still present. |
| Wrong token | Exit 1; `unauthorized`. |
| No token | Exit 2; `missing_machine_token`, no request sent. |
| `shutdown.sh` | Stack stopped; named volumes preserved. |

`setup.sh` still reuses an existing `cloud-control` image; this run rebuilt it
first with `docker compose build cloud-control`, as in TES-76.

No credentials, host addresses, or operator identifiers are included here.
