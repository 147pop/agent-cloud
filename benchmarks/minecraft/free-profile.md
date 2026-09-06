# Optimized free profile

Status: `Experimental`. [TES-140](https://linear.app/workspace/issue/TES-140) tracks acceptance. The recipe and limits are pinned in [free-profile.json](free-profile.json) and [compose.free.yml](compose.free.yml). No player or host capacity is offered yet.

## Candidate selection, 2026-09-06

Compare Paper with Fabric, Lithium and FerriteCore. Add Fabric with C2ME only if generation is a measured bottleneck. Purpur's [FAQ](https://purpurmc.org/docs/purpur/faq/) says its additional options must be enabled to change Paper's behavior, so a separate default-Purpur battery would add little. [Folia](https://github.com/PaperMC/Folia) targets distributed player populations and ideally at least 16 cores. It is outside this four-core study.

The C2ME author's published generation tests support investigating the Fabric family:

| Test, four generation workers | Paper chunks/s | Fabric bundle chunks/s | Relative increase |
| --- | --- | --- | --- |
| [2024, Minecraft 1.21.3](https://gist.github.com/ishland/9601a033afad4be5b17ffaed859577fd) | 36.49 | 48.10 | 32% |
| [2025, Minecraft 1.21.10 with Terralith](https://gist.github.com/ishland/6eb0dd0af4216ffffd340ea994dc5796) | 32.52 | 44.95 | 38% |
| [2026, Minecraft 26.2 with Terralith and Terratonic](https://modrinth.com/mod/c2me-fabric) | 50.55 | 115.08 | 128% |

These are developer benchmarks of bundles with several mods. They used large Xeon hosts, 16 GiB heaps for these rows and RAM-backed storage. Four workers did not limit the whole machine to four cores. Software, worlds and hardware differ between years. The results measure generation throughput; they do not establish Oracle ARM memory use, player experience or concurrent-instance capacity.

[Lithium](https://github.com/CaffeineMC/lithium) optimizes server logic and does not require client installation. [FerriteCore](https://modrinth.com/mod/ferrite-core) reduces selected memory structures. Its published modpack savings do not predict savings in this smaller server. C2ME's measured bundle advantage does not establish an advantage for Lithium and FerriteCore alone.

The independent [Meterstick study, ICPE 2023](https://atlarge-research.com/pdfs/2023-jeickhoff-Meterstick-ICPE2023.pdf), found that relative server performance changed with infrastructure and world activity. Its older game versions do not rank current engines. No independent comparison found in this review qualifies these candidates as multiple small Oracle A1 instances.

## Fixed comparison

Use the existing Oracle A1 host, four Neoverse-N1 cores and about 23.4 GiB Linux-visible RAM. Refresh availability, containers, memory and disk before every battery. Historical E0 directories and the stopped reference container are outside the new runner's mutation scope.

Both candidates use Minecraft 26.2, Temurin 25.0.4, the same pinned container image, two CPU quota units, 2048 MiB heap, 3072 MiB container memory, zero additional swap, seed 20260904, view distance 6 and simulation distance 4. Game containers share CPUs 0-2. CPU 3 is available to the host and synthetic clients. This reserve is part of the measured setup, not a claim that system services never run on another CPU.

Paper uses build 121. Fabric pins loader 0.19.5, launcher 1.1.2, Lithium 0.25.3 and FerriteCore 9.0.0. Mod IDs and SHA-512 hashes are recorded in the profile. The conditional C2ME variant pins 0.4.2-alpha.0.43; its alpha status remains part of the acceptance decision. Do not change Java flags, memory, seed or distances between candidates.

## Workload and predeclared screening rules

1. Validate startup and measurement with a short pilot. Pilot results cannot qualify a profile.
2. Run each candidate with two synthetic players, twice, in a fresh world and then the saved, populated world. Reuse the existing movement and combat driver, adding Survival movement, digging and placement checks. Keep the actions and population identical between engines. Retain failures. The two clients travel in parallel lanes 32 blocks apart, flying 480 blocks out and back in the 60-second scenario. They share much of the loaded terrain. Combat uses creative mode; the final Survival checks cover digging, placement and a short walk. This bounded script does not represent distant players, long sessions or large farms.
3. Compare tick distributions, native gametime, client waits and resource use. If generation dominates a failed or materially slower Fabric run, test the single C2ME variant under the same budget. Repeat a passing variant before selection.
4. Verify the candidate with the same two players travelling on lanes 256 blocks apart, using `--spread`. Repeat that scenario before taking a two-player recipe to the density study. Passing nearby clients does not establish capacity for players loading separate terrain.
5. Test the selected candidate with independent instances sharing the same host and `--spread`. Stagger player phases so active sessions overlap saves and restarts. Increase instance count until the first failed level; repeat the last passing level. Report the tested boundary instead of extrapolating from RAM.
6. Verify clean save/stop, backup, restoration into empty world directories, restart and recovery of markers and population. This local recipe recovery test does not qualify the platform's future R2 or cross-worker recovery.

The screening limits are minimum 19 TPS over measured 60-second windows, every sampled tick p95 at most 50 ms, every sampled tick p99 at most one second, p95 chunk wait at most two seconds, maximum chunk wait at most ten seconds, p95 command response at most 500 ms, maximum command response at most two seconds, and readiness within 180 seconds. Require complete actions and clean persistence checks. These experimental cutoffs are not a player-facing SLA. External human review can reject a synthetic pass.

The preparation probes verified identical native `tick query` output on Paper and Fabric 26.2. It reports mean, p50, p95 and p99 in milliseconds over the last 100 ticks. Read it approximately every five seconds and retain the complete responses. The reported worst sampled p95 is a maximum across windows, not a percentile computed over every tick. Sampling can miss a stall between windows. Native gametime deltas and client waits provide separate observations. Gametime uses query midpoint timestamps. JFR's interval averages from the older study remain a different metric.

Stop on an OOM, less than 2 GiB available host RAM, less than 20 GiB free disk, or a test world crossing the 4 GB soft boundary. Keep game ports bound to loopback and RCON unexposed. Synthetic clients use offline operator identities for repeatability. A deterministic driver supplies the load; no model chooses each movement or scores each tick.

## External acceptance

[TES-142](https://linear.app/workspace/issue/TES-142) owns the controlled comparison and [TES-143](https://linear.app/workspace/issue/TES-143) the concurrent-instance boundary. [TES-144](https://linear.app/workspace/issue/TES-144) requires an authenticated external client, ordinary play, network measurements and human observations on the proposed player route. The public TCP decision remains a separate prerequisite for that route.

Record the client version, approximate location, network context, visible stalls, gameplay differences and reconnect result without publishing identities or credentials. Keep the catalog experimental until this evidence and the automated gates support an explicit capacity decision.

## Reproduce the tests

Use a separate prepared directory on the authorized Oracle host. Copy this directory's scripts, Compose recipe, profile and dependency lockfile. Install the locked bot dependencies and provide the private mode-600 `.env` described in the [benchmark guide](README.md). Do not copy an evidence label or overwrite an existing test world.

```sh
python3 test_free.py
# Run this with the pinned Node image and the benchmark directory mounted at /work:
node protocol26.js
sudo python3 qualify.py comparison-paper --engine paper --players 2 --repeats 2
sudo python3 qualify.py comparison-fabric --engine fabric --players 2 --repeats 2
python3 qualify.py --report evidence/free/comparison-paper
python3 qualify.py --report evidence/free/comparison-fabric
```

For the selected engine, use a new label and `--spread --instances N --seconds 120` for the density study. Run only one battery on the dedicated host at a time. A repeated synthetic pass requires at least 60 continuous seconds with every instance playing in each fresh and populated phase, in both repetitions. Separate short overlaps cannot add up to that minute. Host CPU is sampled from `/proc/stat` and includes the synthetic clients; reported busy CPU excludes idle, I/O wait and steal time. The runner retains test directories and backups, stops its containers, and rejects reused labels. Each formal run archives its exact inputs in `sources.tar.gz` and verifies their hashes after completion. `report_source_sha256` records the separate reporting code used to derive measurements. Remote execution paths and credentials belong in the private operator record.

### Bot protocol correction

The first pilot, `pilot-paper`, failed on block placement before performance qualification. The pinned data package omitted the official teleport-to-entity packet and displaced the final outgoing packet IDs. `protocol26.js` uses the client's supported `customPackets` option to correct the 26.2 mapping. Its serialization check covers digging, placement, animation and teleport-to-entity. The Survival driver also waits for server confirmation of both the removed and replaced block.

The correction was checked against `net.minecraft.network.protocol.game.GameProtocols` in the official 26.2 server JAR, SHA-256 `183c0499c5f855570ee487dd38e141a53f0121f83a0b07a3bac2d8b6698823e8`, using `javap -c -p`. The pinned dependency's `protocol.json` SHA-256 was `fef8c96e9a25905f692b8e1129ab1d331922f4ce41909a56537a4331fff30430`.

| Packet | Official outgoing ID |
| --- | --- |
| Spectator action | `0x3e` |
| Swing arm | `0x3f` |
| Teleport to entity | `0x40` |
| Test instance block action | `0x41` |
| Use item on block | `0x42` |
| Use item | `0x43` |
| Custom click action | `0x44` |

The server versions and resource limits did not change to work around the client failure. Recheck this correction when changing the pinned dependency.

The first formal Fabric attempt, `compare-fabric`, completed its fresh-world player actions but stopped before backup. Fabric had unloaded the marker chunk after the clients disconnected and returned `That position is not loaded`. The runner now temporarily loads the four chunks containing the marker and population area, waits for the server to confirm they are loaded, writes the marker and removes the forced load before backup. The same loaded-chunk check precedes population setup and restart verification. This changes the persistence preparation after players exit. It does not change the active workload, engine configuration or resource limits. The incomplete attempt remains in the evidence export.
