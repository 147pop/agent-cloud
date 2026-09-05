# E0 measurements

The current [Vanilla results](evidence/vanilla-report.md) select **four players and one instance** on Oracle. Configuration and measurement definitions belong in the [Aternos reference](aternos-reference.md).

| Need | File |
| --- | --- |
| Current results | [Vanilla report](evidence/vanilla-report.md) |
| Selected limits | [Vanilla profile](profile.vanilla.json) |
| Earlier Oracle Paper results | [Paper report](../e0-report-2026-09-05.md) |
| Failed shared-host attempts | [Contabo report](evidence/paper-report.md) |
| Disk measurements | [Disk report](evidence/disk-report.md) |
| Network and firewall measurements | [Network report](evidence/network-report.md) |

## Prepare the host

| Requirement | Oracle | Contabo |
| --- | --- | --- |
| Host option | `--host oracle`, ARM64 required | Default |
| Existing containers | None running | Original `cloud-mc-paper-e0` required, no players connected |
| Runtime | Python 3, Docker, Compose, Node 22+ | Same |
| Secrets | Mode-600 `.env` with private `RCON_PASSWORD` | Same |
| Bot dependencies | `npm ci --ignore-scripts --no-audit --no-fund` | Same |

The runner creates a separate game container and fresh world per case. It preserves the original recipe and world. Salta, PostgreSQL and Caddy are outside its mutation scope.

## Run or verify

From the prepared Oracle benchmark directory, use a new label:

```sh
sudo python3 run.py NEW_LABEL --host oracle --vanilla
```

For the historical Paper recipe, omit `--vanilla`. The defaults run 1, 2, 4 and 8 players twice. A short smoke can use `--players 1 --seconds 10 --repeats 1`; it does not qualify the full workload.

From the repository benchmark directory:

```sh
python3 summarize.py evidence/vanilla-acceptance
python3 summarize.py --self-test
```

Existing labels are rejected. Every label owns fresh data and evidence directories with source hashes, `summary.json`, metrics, player events and server logs.

## Scenario

| Step | Action | Required proof |
| --- | --- | --- |
| Start | Fresh world, seed `20260904` | Container health and Minecraft status response |
| Explore | Fly 480 blocks at height 300, 16-block steps | Server-confirmed endpoint per player |
| Return | Follow the loaded route | Server-confirmed return endpoint |
| Combat | Fight summoned husks for 60 seconds | At least one attributed hit per player |
| Persist | Save, stop and restart | Same block marker recovered |

Clients wait up to 60 seconds for each destination chunk. Waiting counts toward phase duration. Socket counters include login and waiting, but exclude IP overhead and Internet latency.

Bots run in a separate one-core/1 GiB container. They use offline operator identities. The game binds only to `127.0.0.1:25566`; RCON has no host port.

## Limits and cleanup

| Stop condition | Threshold |
| --- | --- |
| Protected app on Contabo | HTTP error or response over 1 second |
| Available host RAM | Below 1 GiB |
| Free disk | Below 20 GiB |
| Benchmark memory | OOM |

On Contabo, cleanup restores the original Paper container and checks protected container identities and start times. Oracle has no original Paper or protected application to restore or probe.

A completed run requires actions, marker recovery and cleanup. Performance qualification also requires both repetitions to meet TPS and tick-time thresholds. See the [Vanilla definitions](aternos-reference.md); Paper uses minimum sampled one-minute TPS >=19 and p95 sampled five-second mean tick time <=50 ms.

## Disk and network tools

| Tool | Use |
| --- | --- |
| `disk.py` | Temporary 256 MiB direct synchronous I/O test; see [commands and pacing](evidence/disk-report.md) |
| `network.py` | Both transfer directions, pings and MTU probes; see [setup and cleanup](evidence/network-report.md) |
| `firewall.py` | Temporary listeners and positive-local/negative-external probes |

Firewall listeners use TCP 2379, 2380, 6443, 10250 and UDP 8472, 51820, 51821. They expire after 120 seconds and do not change rules.

```sh
python3 firewall.py serve
python3 firewall.py probe --expect open
```

While listeners are active, probe from an external machine, then repeat the local check:

```sh
python3 firewall.py probe --host PUBLIC_IP --expect blocked
```

Network tests need temporary Oracle TCP/UDP 5201 and ICMP access restricted to Contabo. TCP targets 50 Mbit/s, UDP 5 Mbit/s; use application and Linux socket pacing. Stop iperf and remove temporary ingress afterward.

## Dependencies

The lockfile pins the [26.2-compatible Mineflayer distribution](https://github.com/Complexity-ML/mineflayer-26.2), used because [upstream lacked 26.2 support](https://github.com/PrismarineJS/mineflayer/issues/3940) when this benchmark was prepared. This dependency is confined to the tests.

Paper metrics use its [TPS/MSPT commands](https://docs.papermc.io/paper/reference/commands/); Vanilla uses native counters and JFR. Heap sampling uses the image's `jattach`. Spark's asynchronous RCON output was incomplete in the initial probe.
