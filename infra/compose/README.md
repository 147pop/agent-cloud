# Single-host Docker Compose foundation

This is the supported local installation for one Linux or macOS computer on
the announced arm64 and amd64 platforms. It runs PostgreSQL, `cloud-control`
and one fixed Paper `game-1` service. The K3s installation remains historical
two-host evidence and is not required by this quickstart.

## Requirements

- Git
- Docker Engine or Docker Desktop with Compose v2
- An operator-owned machine token with at least 20 bytes
- Explicit acceptance of the Minecraft EULA
- Resources available to Docker: at least 2 CPUs, 4 GiB RAM and 4 GiB free
  disk (see below)

### Resources and storage

`game-1` runs with the qualified profile limits: 2 CPUs, a 2 GiB Java heap
and a 3 GiB container memory limit. `cloud-control` and PostgreSQL have no
limits. Measured on macOS 26.5 arm64 with Docker Desktop (TES-86 evidence),
with the server running and idle:

| Component | RAM | CPU | Disk |
| --- | --- | --- | --- |
| `game-1` (Paper) | 1.6 GiB, capped at 3 GiB | 3–12% of one CPU | 347 MB image, 245 MB world volume |
| `cloud-control` | 20 MiB | < 1% | 349 MB image |
| PostgreSQL | 25 MiB | < 1% | 638 MB image, 48 MB volume |

Plan for 3.5 GiB RAM for the stack plus the Docker and host overhead. With
Docker Desktop this budget comes from the Docker VM (Settings → Resources),
not the whole computer; keep at least 4 GiB assigned to it. The images need
about 1.4 GB. Player activity grows the world. These numbers are one idle
measurement, not a performance qualification for every host; the active
two-player qualification remains the Oracle A1 evidence.

Named volumes have no filesystem quota: the world and PostgreSQL share the
free space of the filesystem that holds Docker data (`/var/lib/docker` on
Linux, the Docker Desktop disk image on macOS). `cloud-control` mounts the
world volume read-only and refuses to create a new server while that
filesystem has less than `STORAGE_MIN_FREE_MIB` (default 2048) free, with
`507 {"error":"insufficient_storage"}`. The refusal changes no data and does
not consume the request ID, so the same request can be retried after freeing
space. The check applies to creation only; a running world is not stopped
when space runs low, so monitor free space.

Copy the example configuration and edit it without committing the result:

```sh
cp infra/compose/config.example.env .env
chmod 600 .env
```

Set `CLOUD_MACHINE_TOKEN`, `POSTGRES_PASSWORD` and `MINECRAFT_EULA=TRUE`.
The configuration exposes the control API and game port on loopback by
default. PostgreSQL, RCON and the Docker socket are private to the Compose
project. Only `cloud-control` receives the Docker socket; the Paper container
does not receive host or Docker credentials.

## Setup and lifecycle

Run setup from the repository root:

```sh
bash infra/compose/setup.sh
```

Setup validates the Compose file, starts PostgreSQL, creates `game-1` stopped,
and starts `cloud-control`. The game container has the fixed Compose labels
that the Docker runtime verifies before every operation. The runtime owns its
start and stop calls; it reports playable only after the container healthcheck
completes a Minecraft protocol status request.

Create and inspect the one logical server through the current REST contract:

```sh
curl -X POST http://127.0.0.1:3000/v1/servers \
  -H "Authorization: Bearer $CLOUD_MACHINE_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"client_request_id":"create-one","name":"one","eula_accepted":true}'
```

Poll the returned `status_url` until it reports `running` and an endpoint.
Stop and start the same server, and its world, with a new request ID each time:

```sh
curl -X POST http://127.0.0.1:3000/v1/servers/<server_id>/stop \
  -H "Authorization: Bearer $CLOUD_MACHINE_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"client_request_id":"stop-one"}'
```

Stop becomes `stopped` only after Paper exits through its save grace period.
`/start` takes the same body.

Agents can run the same flow over MCP at `http://127.0.0.1:3000/mcp` with the
same bearer header, using the `minecraft_create`, `minecraft_status`,
`minecraft_stop` and `minecraft_start` tools.

Operators can use the CLI with the same token from the environment:

```sh
npm ci && npm run build
set -a; . ./.env; set +a
npm run -s cloud -- create one --accept-eula --wait
npm run -s cloud -- stop <server_id> --wait
npm run -s cloud -- start <server_id> --wait
```

It prints the request ID and state and, after readiness, the game endpoint.

## Game endpoint

`game-1` publishes one fixed port, `GAME_PORT` (default `25565`), on
`GAME_BIND_ADDRESS` (default `127.0.0.1`), and `cloud-control` reports exactly
that address. The endpoint appears in status only while the server is
`running`, which requires a successful Minecraft protocol status request.
Stop/start, container recreation and `setup.sh` reapplication keep the same
address and world volume. Point a Minecraft client at the reported
`host:port`.

LAN or public exposure is an explicit operator choice: set
`GAME_BIND_ADDRESS` to one reachable host interface address (setup rejects
`0.0.0.0` and `::`), rerun setup and verify that path separately, including
firewalls. Optional DNS names are covered by TES-75.

Stop the installation safely:

```sh
bash infra/compose/shutdown.sh
```

The script stops cloud-control first so reconciliation cannot restart Paper,
then stops Paper with its 120-second save grace period and finally PostgreSQL.
Named volumes preserve PostgreSQL and the world across
shutdown, container recreation and setup reapplication. `docker compose down`
also preserves named volumes. Removing them is a separate destructive command:

```sh
bash infra/compose/destroy.sh --yes
```

The one-server capacity limit is deliberate. A distinct second create returns
`409 {"error":"capacity_unavailable"}` and cannot replace the existing owner,
world or endpoint.

## Journey automation

`infra/compose/journey.sh` automates the complete agent-to-play journey
against one clean Compose installation: setup, typed-error checks, REST
create and status polling, a real Minecraft protocol handshake, MCP tools,
CLI use, a world marker across stop and start, second-create capacity and a
safe shutdown that preserves the named volumes.

```sh
bash infra/compose/journey.sh --accept-eula
bash infra/compose/journey.sh --accept-eula --clone /tmp/cloud-journey
```

The script refuses to run when `cloud-*` containers exist; pass `--fresh` to
destroy the named volumes first (destructive). It reads the same `.env` as
setup and generates one with random credentials when missing, never printing
the values. `--clone DIR` clones the current checkout to prove the journey
from a fresh tree; `--no-install` skips `npm ci` and `npm run build` for
repeat runs. Each step prints its own duration and the script exits non-zero
on the first failure. F4.1 evidence lives in
`infra/evidence/tes-155-agent-to-play-journey.md`.

## Verification

Run package checks from the repository root:

```sh
npm ci
npm run check
bash infra/compose/test.sh
```

The focused Docker runtime tests cover Compose identity checks, absent and
stopped containers, protocol readiness, idempotent start/stop and clean
termination. A real Compose run must additionally record the exact commit,
OS, architecture, Docker/Compose versions, durations, world marker and any
failures in the linked Linear acceptance task. Do not commit `.env` or
private runtime logs.
