# E0 benchmark

Run instructions and evidence index. Results, decisions and pending tests are in [Linear](https://linear.app/workspace/issue/TES-24).

| Record | Files |
| --- | --- |
| Vanilla on Oracle | [Settings](aternos-reference.md), [profile](profile.vanilla.json), [summary](evidence/vanilla-acceptance/summary.json), [measurements](evidence/vanilla-measurements.json) |
| Earlier Paper on Oracle | [Profile](profile.json), [summary](evidence/oracle-acceptance/summary.json), [measurements](evidence/oracle-measurements.json) |
| Earlier Paper on Contabo | [Two-core attempt](evidence/acceptance3/summary.json), [three-core attempt](evidence/profile3cpu/summary.json), [measurements](evidence/paper-measurements.json) |
| Disk | [Contabo](evidence/disk-20260905.json), [Oracle](evidence/disk-oracle-20260905.json), [results](https://linear.app/workspace/issue/TES-51) |
| Network | [Accepted attempt](evidence/network-paced-20260905/summary.json), [earlier attempt](evidence/network-20260905/summary.json), [measurements](evidence/network-measurements.json), [results](https://linear.app/workspace/issue/TES-52) |

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
python3 summarize.py evidence/oracle-acceptance
python3 summarize.py --self-test
```

Verify exported files with `shasum -a 256 -c SHA256SUMS` from the corresponding acceptance evidence directory.

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

## Disk

`disk.py` uses a temporary 256 MiB file and direct synchronous I/O, one outstanding operation at a time. Each of four phases performs 256 operations. Sequential operations use 1 MiB and a 20 ms pause; random operations use 4 KiB and a 10 ms pause. Throughput includes pauses and does not measure maximum disk capacity. The script removes its test file without dropping caches or writing to raw devices.

Run from the benchmark directory with a new output name:

```sh
# Contabo
ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json
# Oracle, no protected application probe
sudo ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json --host oracle
```

## Network

Network tests need temporary Oracle TCP/UDP 5201 and ICMP access restricted to Contabo. Start `iperf3 -4 -s --server-bitrate-limit 60M` on Oracle. From Contabo, run:

```sh
python3 network.py 203.0.113.11 evidence/NEW_LABEL
```

The script tests both transfer directions for 20 seconds, targeting 50 Mbit/s TCP and 5 Mbit/s UDP with 1200-byte datagrams. It uses application and Linux socket pacing. These rates do not measure maximum link capacity. Keep the 60 Mbit/s server guard.

Run the reverse ICMP probes from Oracle:

```sh
ping -4 -n -D -i 0.2 -c 100 -W 2 203.0.113.12
ping -4 -n -M do -s 1472 -c 3 -W 2 203.0.113.12
ping -4 -n -M do -s 1473 -c 3 -W 2 203.0.113.12
```

The last probe is expected to fail on the measured path. Retain its error text. Stop iperf and remove temporary ingress from the OCI NSG, runtime firewall and persistent rules afterward. Verify fresh SSH access. See the [Iperf manual](https://software.es.net/iperf/invoking.html) for pacing and reverse mode.

### Firewall probes

Firewall listeners use TCP 2379, 2380, 6443, 10250 and UDP 8472, 51820, 51821. They expire after 120 seconds and do not change rules.

```sh
python3 firewall.py serve
python3 firewall.py probe --expect open
```

While listeners are active, probe from an external machine, then repeat the local check:

```sh
python3 firewall.py probe --host PUBLIC_IP --expect blocked
```

## Dependencies

The lockfile pins the [26.2-compatible Mineflayer distribution](https://github.com/Complexity-ML/mineflayer-26.2), used because [upstream lacked 26.2 support](https://github.com/PrismarineJS/mineflayer/issues/3940) when this benchmark was prepared. This dependency is confined to the tests.

Paper metrics use its [TPS/MSPT commands](https://docs.papermc.io/paper/reference/commands/); Vanilla uses native counters and JFR. Heap sampling uses the image's `jattach`. Spark's asynchronous RCON output was incomplete in the initial probe.
