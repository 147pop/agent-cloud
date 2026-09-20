# TES-156 persistence, idempotency and control-restart trials evidence

Date: 2026-09-20

Branch: `agustinpedernera147/tes-156-f42-verify-persistence-idempotency-and-control-restart-on`

Base: `b5cca04` (`origin/main`, includes the merged F4.1 journey)

Implementation commit:

- `a9bd860` extracts the shared journey helpers into
  `infra/compose/journey-lib.sh`, keeps `journey.sh` behavior unchanged on
  top of it, adds `infra/compose/trials.sh` (the adversarial trials) and
  documents both scripts in `infra/compose/README.md`.

## Verification

`npm run check`

- TypeScript build passed.
- 25 compiled unit tests passed; 0 failed, skipped, or cancelled.

`bash infra/compose/test.sh`: passed (`bash -n` covers `journey-lib.sh` and
`trials.sh`; the protocol client is still `node --check`ed).

`python3 benchmarks/minecraft/summarize.py --self-test`: passed;
`benchmarks/minecraft/` is unchanged.

## Real Compose run

Host: macOS 26.5 arm64, Docker Engine 28.4.0, Compose 2.39.4-desktop.1.
Executed `bash infra/compose/trials.sh --accept-eula --fresh --clone
/tmp/cloud-trials`: the script cloned the branch checkout, generated a
random local `.env` (never printed), destroyed the previous named volumes,
rebuilt and set up the stack inside the clone, then ran the trials.
Total duration 121 s. Each step is asserted and the script exits non-zero
on the first failure.

| Trial | Result |
| --- | --- |
| Competing creates | Three concurrent distinct creates: exactly one `202`; the other two got `409 capacity_unavailable`. PostgreSQL held 1 `servers` row and 1 `idempotency_keys` row (rejected claims rolled back). |
| Status until running | `running` after 30 s; endpoint `127.0.0.1:25565`; protocol ping `Paper 26.2`, protocol 776. |
| Idempotent create replay | Same key and body returned `202` with the same `server_id`; still 1 server row and 1 claimed key. |
| Changed body on the same key | `409 {"error":"idempotency_key_reused"}`. |
| Same key on a different operation | `POST .../stop` with the create key returned `409 idempotency_key_reused`; key count unchanged. |
| World marker | Written and read back in `/data`. |
| REST stop + replay | `stopped` after 2 s; replaying the same key returned `202` with the recorded `stopping` response and same `server_id`; 2 claimed keys. |
| Control restart during start | `docker restart -t 2 cloud-control` issued right after the accepted start; `running` after 22 s; marker preserved; start replay returned the recorded response; 3 claimed keys. |
| Control restart during stop | Restart issued right after the accepted stop; `stopped` after 2 s; 4 claimed keys. |
| Container recreation | `docker compose up -d --force-recreate game-1` produced a new container ID; healthy after 20 s; same endpoint; marker preserved; 5 claimed keys. |
| Single-writer invariants | Exactly one `cloud-game-1` container (running), one `servers` row, one active `runs` row. |
| Clean shutdown | Stack stopped; `cloud_game-world` and `cloud_postgres-data` preserved. |

After each converged trial the script asserts agreement between the API
`state`, the durable `servers`/`runs`/`idempotency_keys` rows and the
observed Docker container state and health, including the endpoint exposed
to clients (`d.endpoint` present only while `running`).

No credentials, host addresses, or operator identifiers are included here.
