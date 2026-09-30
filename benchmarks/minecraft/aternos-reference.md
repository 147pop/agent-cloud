# Aternos reference and test settings

This historical experiment used Aternos' published example of Vanilla 1.20.1 with 2400 MB RAM. Aternos does not publish its full CPU/JVM configuration.

| Aternos publishes | Our local interpretation |
| --- | --- |
| Vanilla 1.20.1 | Official Mojang server, no plugins or mods |
| 2400 MB RAM | 2400 MiB Java heap |
| No published heap/native split | 800 MiB native allowance, 3200 MiB total container cap |

This test did not use a 2400 MB total-container cap. It reproduces the published example with explicit local choices; it does not establish Aternos' private host settings.

Sources checked on 2026-09-05: [Aternos RAM](https://support.aternos.org/hc/en-us/articles/12046003680157-Server-RAM) and [view distance](https://support.aternos.org/hc/en-us/articles/360032974492-View-render-distance-and-fog).

## Exact recipe

| Setting | Value |
| --- | --- |
| Java | Temurin 17.0.15+6, pinned ARM64 image |
| Heap | `-Xms2400M -Xmx2400M`, 2,516,582,400 bytes |
| Container | 3200 MiB, no extra swap |
| CPU | 3 cores on Oracle A1 |
| View / simulation distance | 6 / 4 |
| Seed | `20260904` |
| Test admission ceiling | 8 players |
| Clients | Offline operator bots, creative flight, loopback listener |

CPU, distances, seed and client setup are local choices. The [historical profile](profile.vanilla.json) records four qualified bots under this test's rules. It is not a user-facing offer. The test ceiling stays at eight for reproduction.

The [Compose override](compose.vanilla.yml) pins the runtime. Mojang's [1.20.1 metadata](https://piston-meta.mojang.com/v1/packages/19f5ae58f9c31bd3b0923cb822e99e3162bd62ab/1.20.1.json) requires Java 17 and links the [server JAR](https://piston-data.mojang.com/v1/objects/84194a2f286ef7c14ed7ce0090dba59902951553/server.jar).

Verified JAR SHA-1: `84194a2f286ef7c14ed7ce0090dba59902951553`. SHA-256: `3af73a9dc5a102e38147946360dd27d4d70bae7055bf91cf2151cd5d121b79e0`. The runner checks effective limits and records hashes for each case.

## Measurement rule

A player count qualifies only if both repetitions pass actions, persistence and these thresholds:

| Metric | Threshold | Method |
| --- | --- | --- |
| Lowest available one-minute TPS | At least 19 | Native `time query gametime` deltas |
| p95 reported mean tick time | At most 50 ms | Native JFR `minecraft.ServerTickTime` events |

TPS uses query midpoint timestamps and an earlier observation at least 60 seconds away, normally 60 to 66 seconds. Only available windows ending during actions count. They can include earlier connection work; short first phases may have no full window.

Phase averages use observations within the phase and retain their actual durations. Query time is recorded so timing uncertainty remains visible.

JFR reports average tick duration about once per second. Its p95 is of reported averages, not individual ticks or Paper's five-second means. [Mojang profiler documentation](https://feedback.minecraft.net/hc/en-us/articles/4415128577293-Minecraft-Java-Edition-1-18)

## Scope and evidence

| Check | Scope |
| --- | --- |
| Cases | 1, 2, 4 and 8 players, twice each, fresh worlds |
| Functional proof | Movement, attributed hits, save, stop and marker recovery |
| Memory | Heap, process RSS and container use measured separately |
| Guards | Host memory, free disk and OOM |
| Network | Bots share Oracle; no Internet-player latency |
| Export | Filtered tick JSON only; full JFR stays on Oracle |

Full JFR can contain environment variables. Keys, `.env` and world archives are excluded from the repository export.

[Results and run commands](README.md) · Recorded result in Linear
