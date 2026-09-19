# TES-86 Compose resources and storage evidence

Date: 2026-09-19

Branch: `agustinpedernera147/tes-86-f31-verify-resources-and-persistent-storage-for-one-compose`

Base: `5e0b72b` (`origin/main` when work began)

## Change

- `cloud-control` refuses a new server with `507 insufficient_storage` when
  the world volume's filesystem has less than `STORAGE_MIN_FREE_MIB` (default
  2048) free. The check uses `statfs` on the world volume, mounted read-only,
  runs after idempotent replay and before the capacity gate, and rolls back
  without recording the request ID.
- `game-1` has the qualified profile limits in Compose: `cpus: 2`,
  `mem_limit: 3g`.
- The quickstart states measured resources, the Docker Desktop budget and the
  actual storage guarantee.

## Verification

`npm run check`: TypeScript build passed; 25 unit tests passed, 0 failed,
skipped, or cancelled. The new test checks the exact byte boundary.

`TEST_DATABASE_URL='<disposable PostgreSQL URL>' npm run test:integration`:
PostgreSQL 17.6 in a temporary container; 26 integration tests passed, 0
failed, skipped, or cancelled. The new test proves that a low-space create
leaves no server and no idempotency key, and the same request ID then succeeds
and replays.

`bash infra/compose/test.sh`: passed.
`python3 benchmarks/minecraft/summarize.py --self-test`: passed;
`benchmarks/minecraft/` is unchanged.

## Real Compose run

Host: macOS 26.5 arm64, Docker Desktop (Engine 28.4.0, Compose 2.39.4). The
Docker VM had 10 CPUs and 7.65 GiB RAM. The existing named volumes and
logical server from TES-160/TES-77 were kept.

| Step | Result |
| --- | --- |
| `setup.sh` with the new Compose file | `game-1` recreated stopped with `NanoCpus=2000000000`, `Memory=3221225472`; world files and TES-160 marker present. |
| `start --wait` | `running` after 17 s, endpoint `127.0.0.1:25565`. |
| `df` of `/game-world` inside `cloud-control` | 414 694 MiB free on the Docker Desktop disk. |
| Setup reapplied with `STORAGE_MIN_FREE_MIB` = free + 1024 | `create two`: exit 1, `insufficient_storage`. `game-1` same container, still healthy. |
| Setup reapplied with `STORAGE_MIN_FREE_MIB` = free − 1024 | `create two`: exit 1, `capacity_unavailable`; the storage check passed. |
| PostgreSQL after both | 1 server row; 0 idempotency keys for the rejected requests. |
| Setup reapplied with defaults | Same server running with the same endpoint; marker present. |
| `shutdown.sh` | Paper exit code 0, not OOM-killed; volumes preserved. |

Resource samples, six `docker stats` readings 10 s apart, server running with
no players:

| Container | RAM | CPU |
| --- | --- | --- |
| `cloud-game-1` | 1.622–1.627 GiB of 3 GiB | 2.8–12.0% |
| `cloud-control` | 19.3–19.8 MiB | 0.2–0.7% |
| `cloud-postgres` | 23.0–25.5 MiB | 0.1–0.3% |

Disk: game image 347 MB (arm64), `cloud-control` image 349 MB, PostgreSQL
image 638 MB; `cloud_game-world` 245 MB (world 7 MB, libraries 81 MB,
Paper jar 62 MB, versions 28 MB); `cloud_postgres-data` 48 MB.

Not covered: player load on this host, amd64 and Linux hosts, and a real
filesystem fill to exhaustion. The boundary was exercised by moving the
configured reserve across the measured free space.

No credentials, host addresses, or operator identifiers are included here.
