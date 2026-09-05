# E0 measurements

The current target is [Aternos' Vanilla 1.20.1 / 2400 MB reference](aternos-reference.md), requested on 2026-09-05. The completed [Vanilla results](evidence/vanilla-report.md) qualify four players under the measured rule; eight completed the actions but failed early one-minute TPS windows. The [selected profile](profile.vanilla.json) uses a 2400 MiB heap and 3200 MiB total container cap. These local memory units and limits are not a verified copy of Aternos' private configuration. Use `run.py LABEL --host oracle --vanilla` to reproduce it.

TES-51 measures the shared Contabo disk. TES-55 runs fixed player scenarios. TES-56 records their resource use and selects a beta profile from the results.

The benchmark uses a separate game container and fresh worlds. It preserves `infra/paper/docker-compose.yml` and the existing world. Salta Cyber Club, PostgreSQL and Caddy are outside its mutation scope.

Run `disk.py` on the authorized Linux host. It creates a temporary 256 MiB file, uses direct synchronous I/O at queue depth one, records every operation, and removes the file. The pauses limit load. Reported throughput includes those pauses and is not the disk's maximum throughput.

```sh
ionice -c3 nice -n 19 python3 disk.py evidence/disk.json
```

The Paper runner requires Python 3, Docker, Compose and the existing `cloud-mc-paper-e0` container. Install the bot dependencies in this directory with `npm ci --ignore-scripts --no-audit --no-fund` using Node 22 or newer. Create a mode-600 `.env` containing a private `RCON_PASSWORD`. The runner supplies `BENCH_DATA` for each fresh world.

On the dedicated Oracle ARM host, use `--host oracle` for both `disk.py` and `run.py`. The game runner requires ARM64 and no running containers. That host has no original Paper container or Salta application to stop or probe. The same memory, disk and OOM guards apply. The pinned game images support ARM64.

```sh
sudo python3 run.py trial --players 1 --seconds 10 --repeats 1
sudo python3 run.py acceptance
```

The default run repeats the 1, 2, 4 and 8 player cases twice. Each case starts a fresh world with seed `20260904`, generates chunks by flying through separate lanes, revisits the same route, fights summoned husks, flushes a save, stops, restarts and checks a persisted block. Player logs contain movements, loaded chunks, attacks, damage events and socket byte counters. Socket traffic measures Minecraft TCP payload, excluding TCP/IP overhead and player Internet latency.

Each default route covers 480 blocks at height 300 in 16-block steps. The clients wait up to 60 seconds for each destination chunk before moving. Waiting remains part of the measured phase. Paper confirms each route endpoint through an in-game position condition. Combat lasts 60 seconds on separate platforms. Damage packets must attribute at least one hit to each player. Network counters include login and waiting; player time runs from spawn to scenario completion.

`compose.yml` fixes the Paper image digest, version 26.2 and build 121. The candidate gets three CPU cores, a 4 GiB Java heap and a 5 GiB container memory limit, with view distance 6 and simulation distance 4. Bots have a separate one-core, 1 GiB container limit.

The earlier Oracle ARM Paper battery qualified one player in both repetitions. Its [historical profile](profile.json) reserves one CPU core, 2 GiB of memory and 20 GiB of free disk for the host, and allows one Paper instance. Read the [Paper E0 report](../e0-report-2026-09-05.md) for all eight results and their limits. The benchmark keeps `MAX_PLAYERS=8` to reproduce every case. The current Vanilla profile above replaces that Paper selection for the requested reference.

The two-core candidate at commit `e731fcd` completed one round of all four player counts in `evidence/acceptance3`. Counts 2, 4 and 8 fell below the TPS threshold. A protected-app response of 1.186 seconds stopped the second round. A subsequent baseline of 18 requests peaked at 127 ms. The three-core candidate at commit `de938d0` stopped during its first case when a protected-app response took 1.243 seconds. Both runs restored the original Paper container and verified the protected containers. Neither battery qualifies a profile. Read the [measurement report](evidence/paper-report.md) before running further load on this shared host.

The test server uses offline identities and operator access for its bots. It binds only to `127.0.0.1:25566`; RCON has no host port. This authentication setup is only for these private scenarios. The original E0 server's authentication settings are preserved.

The runner refuses to stop the original server if players are connected. It samples the protected application's HTTP endpoint, host memory, cgroup CPU and memory, Java RSS, I/O pressure, TPS, MSPT and JVM heap information. An HTTP error, a response over one second, less than 1 GiB of available host memory, less than 20 GiB of free disk or a benchmark OOM stops the run. Its cleanup restarts the original Paper container and checks that the protected containers kept their identity and start time.

Each label creates new evidence and data directories. Existing labels are rejected. `summary.json`, `metrics.jsonl`, player events and server logs preserve the measurements and failures. A successful `complete` result requires the scenarios, world marker and cleanup checks to pass. These are E0 measurements, not the twenty K3s persistence cycles or the external-user beta.

For Paper, a player count qualifies when both repetitions pass the action and persistence checks, the minimum sampled one-minute TPS is at least 19, and the 95th percentile of sampled five-second mean tick times is at most 50 ms. Only samples inside the three action phases count toward these performance thresholds. Connection and startup costs remain in the raw evidence. A percentile of window averages is not a percentile of individual ticks. The [Vanilla contract](aternos-reference.md) defines its native counter and JFR measurements.

Validate a finished default battery and derive the measurements with `python3 summarize.py evidence/acceptance`. Run `python3 summarize.py --self-test` to check metric parsing.

`firewall.py serve` binds temporary IPv4 listeners on TCP 2379, 2380, 6443 and 10250, and UDP 8472, 51820 and 51821. It exits after 120 seconds. Run `firewall.py probe --expect open` on the host, then `firewall.py probe --host PUBLIC_IP --expect blocked` from an external machine while those listeners remain active. Repeat the local probe afterward. These commands assert the expected result and print dated JSON. They do not change firewall rules.

With an `iperf3` server on Oracle and TCP/UDP 5201 restricted to Contabo, run `network.py ORACLE_IP evidence/network` on Contabo. It records 100 pings, IPv4 probes around MTU 1500, and 20-second transfers in both directions. TCP targets 50 Mbit/s and UDP 5 Mbit/s with 1200-byte datagrams, using application and Linux socket pacing. The existing app must keep responding within one second. The measured transfer rates are bounded by these targets, not estimates of maximum link capacity. Run the same ping and MTU commands from Oracle toward Contabo to record the reverse path. Remove the temporary 5201 ingress rules and stop iperf afterward.

The bot packages use the [Complexity-ML 26.2 compatibility distribution](https://github.com/Complexity-ML/mineflayer-26.2), because the [upstream client does not yet support 26.2](https://github.com/PrismarineJS/mineflayer/issues/3940). The release URLs and integrity hashes are fixed in `package-lock.json`. This dependency is confined to the benchmark. Tick metrics use Paper's [tps and mspt commands](https://docs.papermc.io/paper/reference/commands/). Heap metrics use the image's existing `jattach` command. Spark's asynchronous responses were incomplete over RCON in the initial probe.
