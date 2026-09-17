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
The later F3 tasks add REST start/stop, MCP and CLI clients over this same
durable contract.

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
