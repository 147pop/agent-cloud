# Earlier Contabo Paper tests, 2026-09-05

Neither Contabo battery qualified a profile. Both stopped when Salta took more than one second to respond. The cause of the slow responses was not established.

| Attempt | CPU cap | Completed work | Why it stopped |
| --- | ---: | --- | --- |
| `acceptance3` | 2 cores | First round, 1/2/4/8 players | Second round: Salta took 1.186 s |
| `profile3cpu` | 3 cores | Partial first case | Salta took 1.243 s |

Later work moved to Oracle. See the [Oracle Paper results](../../e0-report-2026-09-05.md) and the [current Vanilla results](vanilla-report.md).

## Recipe and reproduction record

| Setting | Value |
| --- | --- |
| Host | Contabo `control-host`, `203.0.113.12`, 4 vCPU / 7.8 GiB RAM |
| Server | Paper 26.2 build 121, pinned image in `compose.yml` |
| Heap / container cap | 4 / 5 GiB |
| View / simulation distance | 6 / 4 |
| Seed | `20260904` |
| Bot container | 1 CPU / 1 GiB |

| Evidence | Source | Command |
| --- | --- | --- |
| `pilot8b` | `e731fcd` | `sudo python3 run.py pilot8b --players 8 --seconds 10 --repeats 1` |
| `acceptance3` | `e731fcd` | `sudo python3 run.py acceptance3` |
| `profile3cpu` | `de938d0` | `sudo python3 run.py profile3cpu` |

These labels already exist. Reproduction requires a fresh label and an authorized resolution of the shared-host load issue.

Each default case flies 480 blocks out and back at height 300, then fights husks for 60 seconds. Paper confirms endpoints and attributes damage to each bot. Chunk waits remain inside the action duration.

The shorter `pilot8b` passed movement, damage and marker recovery, but did not qualify the full workload.

## Completed first round, two cores

All four cases completed actions, saved, exited zero and recovered their marker. Only one player met the performance thresholds in this single round; qualification required two rounds.

| Players | Minimum 1m TPS | p95 of 5s mean MSPT |
| ---: | ---: | ---: |
| 1 | 19.1 | 13.9 |
| 2 | 18.6 | 13.6 |
| 4 | 18.3 | 17.2 |
| 8 | 18.5 | 40.8 |

| Players | Cold ready, s | Warm ready, s | Save, s | Stop, s |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 70.47 | 36.98 | 1.00 | 1.58 |
| 2 | 59.70 | 33.02 | 1.82 | 1.78 |
| 4 | 58.01 | 33.95 | 3.73 | 2.71 |
| 8 | 62.08 | 36.96 | 7.86 | 3.20 |

Cold uses fresh data and a cached image; warm restarts the same container and world. Neither timing measures a host reboot.

The rule requires minimum sampled one-minute TPS >=19 and p95 sampled five-second mean tick time <=50 ms. The first TPS windows include earlier activity. Tick-time p95 describes window means, not individual ticks.

| Players | New chunks, s | Existing chunks, s | Combat, s | Total player-seconds waiting for chunks during actions |
|---:|---:|---:|---:|---:|
| 1 | 51.16 | 48.45 | 62.44 | 2.64 |
| 2 | 53.79 | 48.76 | 62.78 | 9.13 |
| 4 | 75.74 | 49.34 | 62.82 | 88.91 |
| 8 | 142.80 | 53.40 | 62.98 | 598.23 |

Eight players took 2.8 times as long as one player to explore their route. TPS alone does not describe terrain waiting.

## Resource samples

| Players | Peak container, GiB | Peak Java RSS, GiB | Peak sampled heap used, GiB |
| ---: | ---: | ---: | ---: |
| 1 | 4.11 | 3.89 | 2.22 |
| 2 | 4.07 | 3.83 | 2.44 |
| 4 | 4.45 | 4.20 | 3.07 |
| 8 | 4.60 | 4.52 | 3.11 |

| Players | Mean / peak CPU cores during actions | World growth, MiB | TCP MiB per player-hour |
| ---: | ---: | ---: | ---: |
| 1 | 0.67 / 1.99 | 10.57 | 105.64 |
| 2 | 0.91 / 1.96 | 17.69 | 87.19 |
| 4 | 1.14 / 1.77 | 33.57 | 70.90 |
| 8 | 1.30 / 2.03 | 66.02 | 49.77 |

CPU comes from cgroup deltas; short sampled peaks can exceed quota. Heap is sampled usage. TCP includes login and waiting but excludes IP overhead, Internet latency and Mojang authentication. [Derived measurements](paper-measurements.json)

## Protection and cleanup

| Check | Result |
| --- | --- |
| `acceptance3` stop time | 03:26:02 UTC, second one-player case |
| Salta after its cleanup | 80 ms |
| Independent 18-request baseline | Maximum 127 ms, no errors |
| `profile3cpu` cold readiness | 55.69 s; actions and persistence incomplete |
| Salta after its cleanup | 81 ms |
| Protected containers | Same IDs, start times and restart counts |
| Original Paper | Restored healthy, zero players |
| Benchmark cleanup | Game stopped, clients removed |

The [baseline](post-abort-baseline.json) and both failed summaries remain stored. No threshold was relaxed. The benchmark did not edit Salta, PostgreSQL, Caddy or the original Paper recipe.

CPU, RAM and player capacity remain unqualified by these attempts. The 4.60 GiB observed container peak does not establish a safe cap for long sessions.

The test kept at least 20 GiB free disk and 1 GiB available host RAM. D3's 4 GB world threshold was not enforced. K3s, public users and recovery were not tested.
