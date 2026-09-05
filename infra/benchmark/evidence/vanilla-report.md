# Aternos Vanilla reference results

The requested **Vanilla 1.20.1 / 2400 MB** comparison completed on Oracle on 2026-09-05. All eight cases passed their actions, save, clean stop and marker recovery. Counts 1, 2 and 4 met the measured performance rule in both repetitions. The [selected E0 profile](../profile.vanilla.json) therefore permits **four players and one instance**, with three CPU cores, a 2400 MiB heap and a 3200 MiB container cap.

Eight players completed both repetitions. During the actions, their observed averages were about 20 TPS, the normal server rate. The first one-minute averages still included time spent connecting and preparing the players, so those readings fell below the 19 TPS threshold. Four passed the complete measured rule twice; eight passed the actions and persistence but missed that initial performance requirement.

## What matches the Aternos reference

[Aternos publishes Vanilla 1.20.1 with 2400 MB RAM](https://support.aternos.org/hc/en-us/articles/12046003680157-Server-RAM). It does not publish a full CPU/JVM recipe, the exact byte unit of its MB label or the heap/native-memory split. The test uses Java's `-Xms2400M -Xmx2400M`, exactly 2,516,582,400 bytes or 2400 MiB, plus an 800 MiB native-memory allowance inside the 3200 MiB container cap. It does not test a 2400 MB total-container cap.

The unmodified Mojang 1.20.1 server uses the pinned Java 17 ARM64 image in [the override](../compose.vanilla.yml). Its JAR SHA-256 is `3af73a9dc5a102e38147946360dd27d4d70bae7055bf91cf2151cd5d121b79e0`; its SHA-1 matches Mojang's published download. Three CPU cores, view distance 6, simulation distance 4 and seed `20260904` are local choices. Aternos does not document them as this example's defaults. The [reference contract](../aternos-reference.md) records the sources and measurement method.

## Reproduction and performance

The run lasted 37.08 minutes, from `2026-09-05T17:30:56.620Z` to `2026-09-05T18:08:01.536Z`. Frozen source and recipe hashes match local commit `638c2c9` and the remote files after execution. All eight cases have identical JAR hashes, selected server properties and verified CPU/heap/container limits. The 26 copied files match their remote hashes, recorded in the [post-run snapshot](oracle-after-vanilla-20260905.json) and [checksums](vanilla-acceptance/SHA256SUMS).

Each case starts a fresh world. Bots fly 480 blocks through separate lanes, return through the loaded route, and fight husks for 60 seconds. The server verifies both endpoints and attributes damage to every player. All 30 player sessions passed these checks, with 1679 confirmed hits. Offline operator bots, creative flight and the loopback listener are test settings. The clients share Oracle and have a separate one-core/1 GiB cap.

The declared rule is minimum available one-minute TPS >=19 and p95 reported mean tick time <=50 ms in both repetitions. TPS comes from game-time deltas, using query midpoint timestamps and windows of 60.01 to 65.59 seconds. Native JFR reports average tick duration about once per second. The p95 below is a percentile of those averages, not individual ticks.

| Case | Minimum TPS, 1m | p95 JFR mean MSPT | New chunks, seconds | Confirmed hits | Measured rule |
| --- | ---: | ---: | ---: | ---: | --- |
| r1-n1 | 19.99 | 12.78 | 48.3 | 56 | Pass |
| r1-n2 | 19.50 | 28.70 | 49.2 | 111 | Pass |
| r1-n4 | 19.15 | 29.44 | 49.9 | 226 | Pass |
| r1-n8 | 15.20 | 40.55 | 81.4 | 446 | Fail |
| r2-n1 | 19.99 | 13.32 | 48.2 | 56 | Pass |
| r2-n2 | 19.09 | 25.89 | 49.1 | 112 | Pass |
| r2-n4 | 19.37 | 29.79 | 49.0 | 225 | Pass |
| r2-n8 | 18.44 | 41.41 | 83.8 | 447 | Fail |

Only available windows ending during an action phase count. A short first phase can have no complete minute window. The worst eight-player windows begin 35.5 and 37.6 seconds before exploration and end about 26 seconds into it. They therefore include the connection/setup workload. Query duration reached 4.10 seconds, so these are timed estimates, not exact tick-boundary measurements. Even allowing the full endpoint-query timing interval, the first eight-player minimum is between 14.95 and 15.44 TPS, below the threshold.

| Eight players on Oracle, Vanilla 1.20.1 | First repetition | Second repetition |
| --- | ---: | ---: |
| New terrain, minimum one-minute TPS | 15.20 | 18.44 |
| Loaded return route, minimum one-minute TPS | 19.99 | 19.67 |
| Combat, minimum one-minute TPS | 19.78 | 19.93 |

Each cell is the lowest average over about 60 seconds observed during that phase. It is not the server's tick rate at one instant. The first row includes the earlier connection/setup work described above. Looking only at the observations within each action phase gives means of 19.99 to 20 TPS. The earlier 18.8 / 19.0 exploration table belongs to Paper, not this Vanilla run.

Phase means use the first and last counter observations within that phase and are capped at the nominal 20 TPS. Their actual observation durations remain in the [derived measurements](vanilla-measurements.json). Eight-player exploration took 81.4 and 83.8 seconds, versus about 48.6 seconds for the loaded return route. Action-phase chunk waits totalled 258.9 and 278.1 player-seconds, with longest individual waits of 2.00 and 2.31 seconds. Near-20 TPS alone does not describe the time spent waiting for terrain.

## Resource and persistence results

| Case | CPU mean / peak, cores | Container peak, MiB | Java RSS peak, MiB | Sampled heap peak, MiB | World growth, MiB | TCP MiB/player-hour |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| r1-n1 | 0.66 / 3.00 | 2590.3 | 2487.9 | 1592.0 | 7.26 | 120.21 |
| r1-n2 | 1.10 / 3.00 | 2583.7 | 2456.9 | 1719.6 | 16.13 | 122.38 |
| r1-n4 | 1.72 / 2.81 | 2998.1 | 2855.4 | 1863.0 | 30.05 | 101.84 |
| r1-n8 | 2.38 / 2.87 | 3159.1 | 2990.0 | 2200.5 | 55.97 | 70.13 |
| r2-n1 | 0.67 / 3.00 | 2751.8 | 2600.4 | 1480.7 | 7.26 | 120.05 |
| r2-n2 | 1.11 / 3.00 | 2702.7 | 2576.0 | 1748.9 | 16.14 | 121.64 |
| r2-n4 | 1.70 / 2.81 | 3018.8 | 2875.9 | 1749.4 | 30.13 | 102.02 |
| r2-n8 | 2.51 / 2.91 | 3155.5 | 3002.2 | 1716.9 | 55.75 | 70.37 |

CPU is cgroup usage between action samples. Container and RSS peaks cover sampled case stages; heap values are sampled usage, not retained live data after a forced collection. TCP counts include login and waiting but exclude IP overhead and Internet latency. Lower per-player traffic at larger counts includes more waiting and does not imply better capacity.

All 432 container samples reported no OOM kill, and all 426 cgroup memory-event records had zero OOM events. Only the eight-player cases recorded `memory.events max`, reaching 912 and 838. These increments first appeared in the post-action save/stop samples, which also cover native JFR export. They show memory-limit pressure during the measured procedure; they do not isolate gameplay from profiling overhead. Four-player cases recorded zero such events.

| Case | Cold ready, seconds | Warm ready, seconds | Save, seconds | Stop, seconds |
| --- | ---: | ---: | ---: | ---: |
| r1-n1 | 52.91 | 22.40 | 0.22 | 4.69 |
| r1-n2 | 52.90 | 22.39 | 0.22 | 3.79 |
| r1-n4 | 52.90 | 26.45 | 0.20 | 3.50 |
| r1-n8 | 52.91 | 22.41 | 1.45 | 3.84 |
| r2-n1 | 52.85 | 22.48 | 0.19 | 4.49 |
| r2-n2 | 52.90 | 26.43 | 0.20 | 3.58 |
| r2-n4 | 52.92 | 26.44 | 0.17 | 3.48 |
| r2-n8 | 52.89 | 22.42 | 2.19 | 4.21 |

Cold readiness starts from fresh data with a cached Docker image; warm readiness restarts the same container and world. Both require container health and a successful Minecraft status query. Every save response succeeded, every checked stop exited zero, and every restarted world retained its block marker.

## Profile and final host state

The selected budget retains three CPU cores, 2400 MiB heap, 3200 MiB container memory with no additional swap, four players, view distance 6 and simulation distance 4. Four-player peaks were 3018.8 MiB container, 2875.9 MiB Java RSS and 1863.0 MiB sampled heap. A smaller CPU or memory cap was not qualified.

Reserve one host core, 2 GiB RAM and at least 20 GiB free disk. Allow one instance under the CPU budget. The lowest sampled available host memory was 19.50 GiB. At 18:08 UTC, a fresh SSH check found no running containers, exit code zero, no benchmark client container and no listener on port 25566. The host had 0.74 GiB used memory, 22.67 GiB available and 38.56 GiB free disk. All eight worlds remain on Oracle.

D3's 4 GB world soft limit is unchanged; its enforcement was not tested. The reserve values are operating budgets, not measurements of future K3s overhead. The earlier [Paper result](../../e0-report-2026-09-05.md) remains historical evidence for Paper 26.2, Java 25 and a 4 GiB heap. Software version, runtime, memory and tick-statistic methods differ, so these runs do not isolate a Vanilla-versus-Paper effect.

The current Vanilla E0 measurement gate is satisfied. K3s deployment, public player access, long survival sessions, R2 backup and worker recovery remain later work. D5's public-address comments still need reconciliation before exposing a game endpoint. Contabo was outside this Vanilla run. Source, evidence and reports remain local; no Git push was performed.

## Verify

From the repository root:

```sh
python3 infra/benchmark/summarize.py infra/benchmark/evidence/vanilla-acceptance
cd infra/benchmark/evidence/vanilla-acceptance
shasum -a 256 -c SHA256SUMS
```

To repeat on the prepared idle Oracle host, use a fresh label from `/home/ubuntu/cloud-minecraft/benchmark`:

```sh
sudo python3 run.py NEW_LABEL --host oracle --vanilla
```

The [runner](../run.py), [players](../players.js), [summarizer](../summarize.py), raw events and native tick JSON reconstruct this result. Full JFR recordings remain on Oracle because they can contain environment variables. No `.env`, private keys, world archives or dependency directories were copied.
