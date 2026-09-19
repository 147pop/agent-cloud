# TES-68 REST start and stop evidence

Date: 2026-09-19

Branch: `agustinpedernera147/tes-68-f312-implement-rest-start-and-stop`

Base: `eee0c41` (`origin/main` when work began)

Implementation commit:

- `8e12de8` routes `POST /v1/servers/{id}/start` and `/stop` to the existing
  durable `ControlStore.mutate` path and documents both routes.

The store, reconciler and Docker runtime already implemented start and stop
(TES-158, TES-202). This task adds the REST surface only.

## Verification

`npm run check`

- TypeScript build passed.
- 17 compiled unit tests passed; 0 failed, skipped, or cancelled.

`TEST_DATABASE_URL='<disposable PostgreSQL URL>' npm run test:integration`

- PostgreSQL 17 ran in a temporary local Docker container.
- 25 integration tests passed; 0 failed, skipped, or cancelled.
- The temporary container was removed after the run.

`python3 benchmarks/minecraft/summarize.py --self-test` passed and
`benchmarks/minecraft/` is unchanged. `bash infra/compose/test.sh` passed.

## Real Compose run

Host: macOS 26.5 arm64, Docker Engine 28.4.0, Compose 2.39.4. Fresh named
volumes; `.env` generated locally and not committed.

| Step | Result |
| --- | --- |
| `setup.sh` | Ready in 26 s; `game-1` created stopped. |
| Create | `202 queued`; `running` with endpoint `127.0.0.1:25565` after 32 s. A marker file was written to `/data`. |
| Stop | `202 stopping` while the container was still running and healthy. |
| Stop replay, same key | `202` with the same fields and values (PostgreSQL `jsonb` reorders keys). |
| Same key, other operation | `409 idempotency_key_reused`. |
| Stop completion | `stopped` after 2 s. Paper logged `All dimensions are saved`; the container exited with code 0 and was not OOM-killed. |
| Start, then `cloud-control` restart 3 s later | `202 queued`; converged to `running` 18 s after the restart. |
| World and port | Same `cloud_game-world` volume, same marker, same `127.0.0.1:25565` endpoint. |
| Start replay, same key | `202` with the original response. |
| `shutdown.sh` | Stack stopped; game exit code 0; named volumes preserved. |

Recorded events for the server, in order: `intent_recorded` create,
`provisioning`, `running`; `intent_recorded` stop, `stopping`, `stopped`;
`intent_recorded` start, `provisioning`, `running`. Each state observation
carries the request ID that caused it.

No credentials, host addresses, or operator identifiers are included here.
