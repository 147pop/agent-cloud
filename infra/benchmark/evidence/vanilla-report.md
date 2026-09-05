# Vanilla results, 2026-09-05

Use **four players and one instance** on Oracle for the tested profile. All eight cases completed actions and world recovery; eight players missed the initial TPS requirement.

| Players | Lowest 1-minute TPS, run 1 | Run 2 | Result |
| --- | ---: | ---: | --- |
| 1 | 19.99 | 19.99 | Pass twice |
| 2 | 19.50 | 19.09 | Pass twice |
| 4 | 19.15 | 19.37 | Pass twice |
| 8 | 15.20 | 18.44 | Fail twice |

The rule requires at least 19 TPS and p95 reported mean tick time at most 50 ms in both runs. Every case passed the tick-time requirement.

## Eight players

20 TPS is the normal server rate. These are the lowest averages over about one minute during each stage.

| Stage | Run 1 | Run 2 |
| --- | ---: | ---: |
| New terrain | 15.20 | 18.44 |
| Loaded return route | 19.99 | 19.67 |
| Combat | 19.78 | 19.93 |

The first row includes 35.5 and 37.6 seconds of connection/setup before exploration. Counter observations contained within each action phase averaged 19.99 to 20 TPS.

| Duration or wait | Run 1 | Run 2 |
| --- | ---: | ---: |
| Exploration duration, seconds | 81.4 | 83.8 |
| Return-route duration, seconds | About 48.6 | About 48.6 |
| Total chunk waits, player-seconds | 258.9 | 278.1 |
| Longest individual wait, seconds | 2.00 | 2.31 |

Eight completed gameplay checks twice, but took longer to load terrain and failed the complete TPS rule. Near-20 action averages do not erase those waits.

## Selected budget

| Resource | Selection |
| --- | --- |
| Software | Unmodified Vanilla 1.20.1, Java 17 ARM64 |
| CPU | 3 cores |
| Java heap / container cap | 2400 / 3200 MiB, no extra swap |
| Players / simultaneous instances | 4 / 1 |
| View / simulation distance | 6 / 4 |
| Host reserve | 1 core, 2 GiB RAM, 20 GiB free disk |
| World policy | D3's 4 GB soft limit; enforcement untested |

Four-player peaks were 3018.8 MiB container memory, 2875.9 MiB Java RSS and 1863.0 MiB sampled heap. Smaller CPU or RAM limits were not qualified. Reserves are operating budgets; future K3s overhead was not measured.

[Selected profile](../profile.vanilla.json) · [Recipe and Aternos sources](../aternos-reference.md)

Aternos publishes Vanilla 1.20.1 with 2400 MB RAM. Our test interprets that as a 2400 MiB Java heap and adds 800 MiB for native memory. CPU, memory split and view settings are local choices, not a verified copy of Aternos' private configuration.

## What the test covered

| Check | Evidence |
| --- | --- |
| Time | 17:30:56.620 to 18:08:01.536 UTC, 37.08 minutes |
| Repetitions | 1, 2, 4 and 8 players, twice each, fresh worlds |
| Actions | 480 blocks out and back; 60 seconds of combat |
| Server-confirmed actions | 30/30 player sessions, 1679 attributed hits |
| Persistence | 8/8 worlds saved, stopped cleanly and recovered their marker |
| Frozen source | `638c2c9`, matched on Oracle after execution |
| Recipe | Identical JAR hashes, properties and effective limits in all cases |
| Copied evidence | 26 files matched their Oracle hashes |

Bots use offline operator identities and creative flight. They share Oracle with the game server in a separate one-core/1 GiB container. The listener is loopback-only; no player Internet latency was measured.

[Run summary](vanilla-acceptance/summary.json) · [Measurements](vanilla-measurements.json) · [Post-run verification](oracle-after-vanilla-20260905.json)

## Reading the metrics

| Metric | Meaning and limit |
| --- | --- |
| TPS | Game-time counter change divided by query midpoint elapsed time |
| One-minute windows | 60.01 to 65.59 seconds; only available windows ending during actions count |
| First exploration window | Can include earlier connection work; a short first phase may have no full window |
| Query timing | Up to 4.10 seconds; first eight-player minimum remains 14.95 to 15.44 TPS across the endpoint timing interval |
| Phase mean | First-to-last observations within that phase, capped at 20 TPS; durations retained in measurements |
| JFR tick time | An average reported about once per second; p95 here is of those averages, not individual ticks |

| Players | p95 JFR mean tick time, run 1, ms | Run 2, ms |
| --- | ---: | ---: |
| 1 | 12.78 | 13.32 |
| 2 | 28.70 | 25.89 |
| 4 | 29.44 | 29.79 |
| 8 | 40.55 | 41.41 |

The earlier [Paper results](../../e0-report-2026-09-05.md) use another server version, Java runtime, memory cap and tick statistic. These runs do not isolate a Vanilla-versus-Paper effect.

## Resource samples

| Case | Container peak, MiB | Java RSS peak, MiB | Sampled heap peak, MiB |
| --- | ---: | ---: | ---: |
| r1-n1 | 2590.3 | 2487.9 | 1592.0 |
| r1-n2 | 2583.7 | 2456.9 | 1719.6 |
| r1-n4 | 2998.1 | 2855.4 | 1863.0 |
| r1-n8 | 3159.1 | 2990.0 | 2200.5 |
| r2-n1 | 2751.8 | 2600.4 | 1480.7 |
| r2-n2 | 2702.7 | 2576.0 | 1748.9 |
| r2-n4 | 3018.8 | 2875.9 | 1749.4 |
| r2-n8 | 3155.5 | 3002.2 | 1716.9 |

| Case | CPU mean / peak, cores | World growth, MiB | TCP MiB/player-hour |
| --- | ---: | ---: | ---: |
| r1-n1 | 0.66 / 3.00 | 7.26 | 120.21 |
| r1-n2 | 1.10 / 3.00 | 16.13 | 122.38 |
| r1-n4 | 1.72 / 2.81 | 30.05 | 101.84 |
| r1-n8 | 2.38 / 2.87 | 55.97 | 70.13 |
| r2-n1 | 0.67 / 3.00 | 7.26 | 120.05 |
| r2-n2 | 1.11 / 3.00 | 16.14 | 121.64 |
| r2-n4 | 1.70 / 2.81 | 30.13 | 102.02 |
| r2-n8 | 2.51 / 2.91 | 55.75 | 70.37 |

CPU covers action samples. Container and RSS peaks cover sampled case stages. Heap is sampled usage. TCP includes login and waiting, but excludes IP overhead and Internet latency; lower per-player traffic can reflect more waiting.

| Memory check | Result |
| --- | --- |
| OOM kills | None in 432 container samples |
| OOM events | Zero in all 426 cgroup event records |
| Four-player memory-limit events | Zero |
| Eight-player memory-limit events | 912 and 838, first seen during save/stop and JFR export |
| Minimum available host RAM | 19.50 GiB |

The eight-player events show memory-limit pressure during the procedure. The samples cannot separate gameplay from profiler overhead.

## Startup and persistence

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

Cold readiness uses fresh data and a cached image. Warm readiness reuses the container and world. Both require container health and a successful Minecraft status query. Every checked stop exited zero and every marker survived restart.

## Final state and remaining work

At 18:08 UTC, Oracle had no running containers or port-25566 listener. Available RAM was 22.67 GiB and free disk 38.56 GiB; all eight worlds remained on disk. Contabo was outside this run.

K3s, public players, long survival sessions, R2 backups and worker recovery remain untested. D5's public-address decision still needs reconciliation.

## Verify or repeat

From the repository root:

```sh
python3 infra/benchmark/summarize.py infra/benchmark/evidence/vanilla-acceptance
cd infra/benchmark/evidence/vanilla-acceptance
shasum -a 256 -c SHA256SUMS
```

On the prepared, idle Oracle host, from `/home/ubuntu/cloud-minecraft/benchmark`, use a fresh label:

```sh
sudo python3 run.py NEW_LABEL --host oracle --vanilla
```

[Runner](../run.py) · [Players](../players.js) · [Summarizer](../summarize.py)

Full JFR recordings remain on Oracle because they can contain environment variables. The repository contains filtered tick events; keys, `.env` and world archives stay outside it.
