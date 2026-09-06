# Minecraft benchmarks

This directory contains the historical E0 study and the optimized free-profile qualification. [Catalog entries](../../catalog/README.md) describe their status. [Linear](https://linear.app/workspace/issue/TES-140) tracks qualification of the optimized free profile.

## Results

The September 2026 study used local synthetic clients. These results do not qualify a public offer.

| Run | Resources and method | Observed result | Evidence |
| --- | --- | --- | --- |
| Vanilla 1.20.1, Oracle ARM64 | 3 CPU cores, 2400 MiB heap, 3200 MiB container; native gametime and JFR | All 8 runs completed actions and persistence. 1, 2 and 4 bots passed the performance rules in both repetitions. 8 bots did not, with lowest minute TPS of 15.20 and 18.44. | [Measurements](evidence/vanilla-measurements.json), [raw run](evidence/vanilla-acceptance/summary.json) |
| Paper 26.2 build 121, Oracle ARM64 | 3 CPU cores, 4 GiB heap, 5 GiB container; Paper TPS/MSPT commands | All 8 runs completed actions and persistence. Only 1 bot passed the performance rules in both repetitions. The longest recorded action chunk wait was 16.25 seconds. | [Measurements](evidence/oracle-measurements.json), [raw run](evidence/oracle-acceptance/summary.json) |
| Paper 26.2 build 121, Contabo | 2-core and 3-core attempts, 4 GiB heap, 5 GiB container | Neither battery completed. The protected application exceeded the 1-second response guard at 1.186 and 1.243 seconds. These attempts provide no accepted capacity. | [2-core attempt](evidence/acceptance3/summary.json), [3-core attempt](evidence/profile3cpu/summary.json), [measurements](evidence/paper-measurements.json) |

The historical threshold was at least 19 TPS and at most 50 ms p95 of reported mean tick times. Vanilla and Paper reported different averages, and their game versions and memory limits differed. This is not a controlled comparison of server engines. Do not rank them from these runs.

Counts of four Vanilla bots are a reference result, not a free-tier specification. Bots used creative flight and local connections. Ordinary play, Internet latency, longer sessions, populated worlds and multiple simultaneous servers remain untested by this study.

## Evidence index

| Record | Files |
| --- | --- |
| Vanilla on Oracle | [Settings](aternos-reference.md), [profile](profile.vanilla.json), [summary](evidence/vanilla-acceptance/summary.json), [measurements](evidence/vanilla-measurements.json) |
| Earlier Paper on Oracle | [Profile](profile.json), [summary](evidence/oracle-acceptance/summary.json), [measurements](evidence/oracle-measurements.json) |
| Earlier Paper on Contabo | [Two-core attempt](evidence/acceptance3/summary.json), [three-core attempt](evidence/profile3cpu/summary.json), [measurements](evidence/paper-measurements.json) |
| Disk | [Contabo](evidence/disk-20260905.json), [Oracle](evidence/disk-oracle-20260905.json), [method and result](#disk) |
| Network | [Completed attempt](evidence/network-paced-20260905/summary.json), [earlier attempt](evidence/network-20260905/summary.json), [measurements](evidence/network-measurements.json), [method and result](#network) |

The move from `infra/benchmark` preserved every exported evidence file. `source_sha256` records the code used by a run; it does not claim that the latest runner is identical. The original sources remain in Git history:

| Run | Source references |
| --- | --- |
| Vanilla acceptance | [Recipe and runner at 050c761](https://github.com/pjcdz/cloud/tree/050c76141f415c522967cdea2790547ed393422c/infra/benchmark) |
| Oracle Paper acceptance | [run.py at 396d001](https://github.com/pjcdz/cloud/blob/396d0011964254985b662c44f2ddb7dadd645739/infra/benchmark/run.py), [players.js at e731fcd](https://github.com/pjcdz/cloud/blob/e731fcdc2530240fb83b8264a5d370aff92edf5b/infra/benchmark/players.js), base recipe and lockfile from [050c761](https://github.com/pjcdz/cloud/tree/050c76141f415c522967cdea2790547ed393422c/infra/benchmark) |
| Contabo Paper attempts | [Runner, players and 2-core recipe at e731fcd](https://github.com/pjcdz/cloud/tree/e731fcdc2530240fb83b8264a5d370aff92edf5b/infra/benchmark); the 3-core attempt used [this base recipe at 050c761](https://github.com/pjcdz/cloud/blob/050c76141f415c522967cdea2790547ed393422c/infra/benchmark/compose.yml) |
| Paced network run | [network.py at 050c761](https://github.com/pjcdz/cloud/blob/050c76141f415c522967cdea2790547ed393422c/infra/benchmark/network.py) with the application guard from [run.py at e731fcd](https://github.com/pjcdz/cloud/blob/e731fcdc2530240fb83b8264a5d370aff92edf5b/infra/benchmark/run.py) |

Profiles and raw files retain their original names and historical decisions. The [catalog](../../catalog/README.md) states whether a profile is currently eligible for an offer.

## Qualifying a free profile

The free tier prioritizes acceptable simultaneous sessions per host. Optimized engines are candidates; the historical Vanilla profile does not select the default.

The [public research and fixed comparison](free-profile.md) narrow the candidates to Paper and Fabric with Lithium and FerriteCore. C2ME is the only conditional variant, for a measured generation bottleneck. The plan pins one Minecraft and Java version, hardware, CPU and memory limits, distances, seed, client workload and measurement method. Record gameplay differences and required client changes.

The [recorded comparison](free-profile-results.md) passed for both nearby-player candidates. Paper also passed the repeated separate-terrain check and the longer density workload with one instance and two players. Two instances exceeded the RCON response limit during a save. On 2026-09-06, Pablo accepted the bot activity and local recovery evidence for E1 profile selection. Paper is Qualified for that scope. [TPS by activity](free-profile-results.md#tps-by-player-activity) covers two repetitions. External human play and the live Spectrum route remain pending before public opening.

Qualification covers these checks:

1. Compare candidates at the same resource limits with fresh and populated worlds. Record the bot workload and keep human observations separate. Measure TPS, tick-time distributions, terrain waits, connection and command latency, memory, CPU and network use.
2. Select a profile only after repeated runs meet written experience thresholds. Explain whether a slow phase reflects world generation, host contention, network delay or the server itself. A 19 TPS rule alone does not define playability.
3. Run multiple independent server instances on one host, including concurrent starts, active sessions and background saves. Measure the number of acceptable sessions and resource use while preserving host reserves.
4. Test save, stop, restart, backup and restore with that profile. Record compatibility and retest requirements for version updates.
5. Use those measurements to define admission limits and an offer. Report cost per concurrent session when the deployment cost is known.

Use [qualify.py](qualify.py) and [compose.free.yml](compose.free.yml) for the new study. The historical [run.py](run.py) runs one E0 benchmark server at a time. Source archives identify the exact runner used by each formal attempt.

## Prepare the host

Hardware observations from September 4 and 5, 2026:

| Host | Region | CPU | Linux-visible RAM | Runtime |
| --- | --- | --- | --- | --- |
| Oracle `VM.Standard.A1.Flex` | Santiago, `sa-santiago-1` | 4 OCPU, Neoverse-N1, ARM64 | 23.41 GiB | Ubuntu 24.04.4, cgroup v2 |
| Contabo | US inferred from GeoIP; provider datacenter unconfirmed | 4 vCPU, AMD EPYC, x86-64 | 7.76 GiB | Ubuntu 24.04.4, cgroup v2 |

The game resource limits are recorded separately in the results table and profiles. Current operator access and full host records are maintained privately in [TES-53](https://linear.app/workspace/issue/TES-53). Historical measurements retain the test endpoints they recorded. These observations are not a live inventory.

| Requirement | Oracle | Contabo |
| --- | --- | --- |
| Host option | `--host oracle`, ARM64 required | Default |
| Existing containers | None running | Original `cloud-mc-paper-e0` required, no players connected |
| Runtime | Python 3, Docker, Compose, Node 22+ | Same |
| Secrets | Mode-600 `.env` with private `RCON_PASSWORD` | Same |
| Bot dependencies | `npm ci --ignore-scripts --no-audit --no-fund` | Same |

These instructions describe the original host setup. Verify the target and its current workload before running a new experiment. The runner creates a separate game container and fresh world per case. It preserves the original recipe and world. Salta, PostgreSQL and Caddy are outside its mutation scope.

## Run or verify

From the prepared Oracle benchmark directory, use a new label:

```sh
sudo python3 run.py NEW_LABEL --host oracle --vanilla
```

For the historical Paper recipe, omit `--vanilla`. The defaults run 1, 2, 4 and 8 players twice. A short smoke can use `--players 1 --seconds 10 --repeats 1`; it does not qualify the full workload.

To verify the saved evidence without starting servers, run from the repository root:

```sh
cd benchmarks/minecraft
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

Both host probes completed. Contabo's p95 random-read/random-write latencies were 0.85/1.33 ms; Oracle's were 0.74/0.80 ms. The measured sequential throughput includes deliberate pauses and is not disk saturation. See the [Contabo](evidence/disk-20260905.json) and [Oracle](evidence/disk-oracle-20260905.json) observations.

`disk.py` uses a temporary 256 MiB file and direct synchronous I/O, one outstanding operation at a time. Each of four phases performs 256 operations. Sequential operations use 1 MiB and a 20 ms pause; random operations use 4 KiB and a 10 ms pause. Throughput includes pauses and does not measure maximum disk capacity. The script removes its test file without dropping caches or writing to raw devices.

Run from the benchmark directory with a new output name:

```sh
# Contabo
ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json
# Oracle, no protected application probe
sudo ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json --host oracle
```

## Network

The paced run measured 194 ms p95 ICMP latency in both directions, with no loss in 100 ICMP packets per direction. TCP received 38.88 Mbit/s from Contabo to Oracle and 49.96 Mbit/s in reverse at a 50 Mbit/s target. The reverse TCP transfer reported 4,914 retransmissions. These observations support [the recorded path result](evidence/network-measurements.json), not a maximum link capacity or player-latency claim.

Network tests need temporary Oracle TCP/UDP 5201 and ICMP access restricted to Contabo. Start `iperf3 -4 -s --server-bitrate-limit 60M` on Oracle. From Contabo, run:

```sh
python3 network.py "$ORACLE_IP" evidence/NEW_LABEL
```

Set `ORACLE_IP` and `CONTABO_IP` to the authorized test endpoints. The script tests both transfer directions for 20 seconds, targeting 50 Mbit/s TCP and 5 Mbit/s UDP with 1200-byte datagrams. It uses application and Linux socket pacing. These rates do not measure maximum link capacity. Keep the 60 Mbit/s server guard.

Run the reverse ICMP probes from Oracle:

```sh
ping -4 -n -D -i 0.2 -c 100 -W 2 "$CONTABO_IP"
ping -4 -n -M do -s 1472 -c 3 -W 2 "$CONTABO_IP"
ping -4 -n -M do -s 1473 -c 3 -W 2 "$CONTABO_IP"
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
