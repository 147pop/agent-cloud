# Paper E0 measurements, 2026-09-05

No beta profile is approved by this run. The two-core candidate completed one round with 1, 2, 4 and 8 players, then a protected-app latency check stopped its second round. The three-core candidate triggered the same check during its first case. Both batteries are incomplete, and their failures remain in the raw evidence.

TES-51 is complete in the [disk report](disk-report.md). TES-55 has a working scenario runner and one complete round, but its full repeatability check remains open. TES-56 remains open because no candidate completed qualification. Further load testing on this shared host needs the protected-app latency issue resolved or an isolated test host.

## Reproduction and inputs

The host was Contabo `control-host`, `203.0.113.12`, with 4 vCPU and 7.8 GiB RAM. Paper used version 26.2, build 121, the pinned image in `compose.yml`, a 4 GiB heap, a 5 GiB container limit, seed `20260904`, view distance 6 and simulation distance 4. The clients used a separate container limited to 1 CPU and 1 GiB. The runner was the only service that stopped and restarted the existing `cloud-mc-paper-e0` container.

| Evidence directory | Source commit | Paper CPU limit | Command |
|---|---|---:|---|
| `pilot8b` | `e731fcd` | 2 | `sudo python3 run.py pilot8b --players 8 --seconds 10 --repeats 1` |
| `acceptance3` | `e731fcd` | 2 | `sudo python3 run.py acceptance3` |
| `profile3cpu` | `de938d0` | 3 | `sudo python3 run.py profile3cpu` |

Each new label creates fresh data. Existing labels are rejected. Use a new label when reproducing. `summary.json` records source and recipe hashes. The completed eight-player pilot confirmed that every client moved, dealt damage and retained the world marker after restart. Its shorter routes do not qualify the full battery.

The default scenarios cover 480 blocks out and back at height 300, then fight AI husks for 60 seconds. Paper confirms each endpoint and attributes damage to each player. Clients wait for missing destination chunks; those waits remain inside the action phase. Cold readiness starts with fresh `/data` and an already cached Docker image. Warm readiness restarts the same container and data. Neither measures a host reboot.

## Completed first round, two CPU cores

All four cases completed the expected routes, confirmed player damage, saved cleanly, exited with code zero and retained the diamond-block marker after restart.

| Players | Cold ready, s | Warm ready, s | Save, s | Stop, s | Minimum 1m TPS | p95 of 5s mean MSPT |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 70.47 | 36.98 | 1.00 | 1.58 | 19.1 | 13.9 |
| 2 | 59.70 | 33.02 | 1.82 | 1.78 | 18.6 | 13.6 |
| 4 | 58.01 | 33.95 | 3.73 | 2.71 | 18.3 | 17.2 |
| 8 | 62.08 | 36.96 | 7.86 | 3.20 | 18.5 | 40.8 |

The declared threshold requires both repetitions to reach at least 19 TPS and no more than 50 ms for the p95 of sampled five-second mean tick times. A percentile of window means is not a percentile of individual ticks. The one-minute TPS statistic also includes earlier server activity. For two players, the below-threshold samples occurred in the first ten seconds of the action phase. They remain failures under the declared rule.

| Players | Mean / peak CPU cores during actions | Peak container, GiB | Peak Java RSS, GiB | Peak sampled heap used, GiB | World growth, MiB | TCP MiB per player-hour |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.67 / 1.99 | 4.11 | 3.89 | 2.22 | 10.57 | 105.64 |
| 2 | 0.91 / 1.96 | 4.07 | 3.83 | 2.44 | 17.69 | 87.19 |
| 4 | 1.14 / 1.77 | 4.45 | 4.20 | 3.07 | 33.57 | 70.90 |
| 8 | 1.30 / 2.03 | 4.60 | 4.52 | 3.11 | 66.02 | 49.77 |

CPU comes from cgroup usage deltas. Small peaks above the quota can occur within sampling windows. Heap is sampled allocated usage, not retained live data after a forced collection. TCP counters include login and waiting, and player time runs from spawn to completion. They exclude IP overhead, Internet latency and Mojang authentication.

| Players | New chunks, s | Existing chunks, s | Combat, s | Total player-seconds waiting for chunks during actions |
|---:|---:|---:|---:|---:|
| 1 | 51.16 | 48.45 | 62.44 | 2.64 |
| 2 | 53.79 | 48.76 | 62.78 | 9.13 |
| 4 | 75.74 | 49.34 | 62.82 | 88.91 |
| 8 | 142.80 | 53.40 | 62.98 | 598.23 |

Eight players took 2.8 times as long as one player to generate the same per-player route. This waiting matters for playability even when TPS is near 20. The [derived values](paper-measurements.json) retain more precision; source events and samples remain in each evidence directory.

## Protection checks and final host state

`acceptance3` stopped at `2026-09-05T03:26:02Z` during the second one-player case after an application response took 1.186 seconds. The threshold was one second. Paper was restored, and its subsequent application probe took 80 ms. An independent [18-request baseline](post-abort-baseline.json), with the original Paper restored and benchmark stopped, peaked at 127 ms without errors.

`profile3cpu` kept the same thresholds and raised only the Paper CPU limit. It stopped during the first one-player case after an application response took 1.243 seconds. Its cold readiness took 55.69 seconds, but it did not finish its actions or persistence check. The application probe after cleanup took 81 ms.

The evidence does not establish the cause of either slow application response. Both cross the protection limit, so neither run is accepted. No protection threshold was relaxed and no failed attempt was discarded.

Both summaries verify that `co-tenant-app` and `co-tenant-db` kept their container IDs, start times and restart counts. The original Paper container was healthy with zero players after cleanup. The benchmark container was stopped and its client container removed. The benchmark did not edit the protected application, database, Caddy or the original Paper recipe.

## Profile decision

CPU, RAM and player count remain unqualified. The observed container peak of 4.60 GiB does not prove a 5 GiB cap is sufficient for long sessions, and a single passing one-player case does not establish repeatability. Increasing Paper to three cores did not produce a completed battery.

The approved D3 storage policy remains a 4 GB soft threshold. These runs measured world growth but did not test or enforce that threshold. The runner preserved at least 20 GiB free disk and 1 GiB available host memory as stop conditions. Those guards are not a final system-reserve or admission policy.

To finish TES-55 and TES-56, resolve the protected-app latency issue within an authorized scope or move the same battery to an isolated host. Then run both repetitions and derive CPU, RAM, player, disk and reserve values from accepted evidence. K3s, twenty persistence cycles, external users, WAN traffic and recovery remain outside this measurement.
