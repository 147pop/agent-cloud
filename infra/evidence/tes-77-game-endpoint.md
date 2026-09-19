# TES-77 stable Compose game endpoint evidence

Date: 2026-09-19

Branch: `agustinpedernera147/tes-77-f315-return-the-stable-compose-game-endpoint`

Base: `8f2c405` (`origin/main` when work began)

## Change

The Docker runtime already reported `CLOUD_GAME_HOST:CLOUD_GAME_PORT` only
while the `game-1` healthcheck passed a Minecraft status request. This task
makes the bind address explicit operator configuration:

- `GAME_BIND_ADDRESS` (default `127.0.0.1`) sets both the published address of
  `game-1` and the host that `cloud-control` reports, so they cannot diverge.
- `setup.sh` rejects `0.0.0.0` and `::`, which are not addresses a client can
  use.
- `infra/compose/README.md` documents the endpoint and LAN exposure.

LAN or public exposure was not exercised; it needs its own verification.

## Verification

`npm run check`: TypeScript build passed; 24 compiled unit tests passed, 0
failed, skipped, or cancelled.

`bash infra/compose/test.sh`: passed.

`python3 benchmarks/minecraft/summarize.py --self-test`: passed;
`benchmarks/minecraft/` is unchanged.

`setup.sh` with `GAME_BIND_ADDRESS=0.0.0.0`: exit 1 with
`GAME_BIND_ADDRESS must be one host address that clients can reach, not 0.0.0.0`.

## Real Compose run

Host: macOS 26.5 arm64, Docker Engine 28.4.0, Compose 2.39.4. `cloud-control`
rebuilt from this branch; the existing named volumes and logical server from
TES-160 were kept. Lifecycle calls used `npm run -s cloud`. The client was a
host-side Minecraft Java protocol client (handshake and status request) aimed
at the reported `host:port`.

| Step | Result |
| --- | --- |
| `setup.sh` | `game-1` published on `127.0.0.1:25565`; `cloud-control` has `CLOUD_GAME_HOST=127.0.0.1`, `CLOUD_GAME_PORT=25565`. |
| Create replay (`cli-create-one`) | Same server ID as TES-160. |
| `start --wait` | `running` after 7 s with endpoint `127.0.0.1:25565`. |
| Client to reported address | `Paper 26.2`, protocol 776, 0/2 players. |
| `stop --wait` | `stopped` after 2 s; exit code 0, not OOM-killed. Status has no endpoint. |
| Client while stopped | `ECONNREFUSED`. |
| `start --wait` | `running` after 13 s, same endpoint. |
| Client reconnect | `Paper 26.2`, protocol 776. |
| `setup.sh` reapplied while running | Same container ID, still running; status and client unchanged. |
| `create two` | Exit 1; `capacity_unavailable`. |
| World marker from TES-160 | Still present in `/data`. |
| `shutdown.sh` | Stack stopped; named volumes preserved. |

No full player login was performed (the server is online-mode); readiness and
reconnection were proven with the Minecraft status protocol.

No credentials, host addresses, or operator identifiers are included here.
