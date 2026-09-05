# Aternos Vanilla reference

The owner requested this comparison on 2026-09-05. The target is the public Aternos example, **Vanilla 1.20.1 with 2400 MB RAM**. The earlier Paper 26.2 benchmark remains evidence for that different recipe. Its one-player qualification does not establish a capacity limit for Vanilla.

The [completed Vanilla battery](evidence/vanilla-report.md) qualifies four players under the measured rule. Eight completed actions and persistence twice but failed the early one-minute TPS windows. The [selected profile](profile.vanilla.json) keeps the explicit local memory interpretation below.

[Aternos' RAM documentation](https://support.aternos.org/hc/en-us/articles/12046003680157-Server-RAM), checked on 2026-09-05, assigns RAM by software and version and gives this example. It does not publish the complete CPU allocation, JVM flags, heap/native-memory split or exact byte interpretation of its MB label. Its [view-distance documentation](https://support.aternos.org/hc/en-us/articles/360032974492-View-render-distance-and-fog) explains the limits but does not give a complete version-specific recipe. This is a reproduction of the documented reference on Oracle, not a verified copy of Aternos' private host configuration.

| Setting | Test value | Source |
| --- | --- | --- |
| Software and version | Mojang Vanilla 1.20.1, no plugins or mods | Aternos' published example |
| RAM label | 2400 MB | Aternos' published example |
| Java heap | `-Xms2400M -Xmx2400M`, exactly 2,516,582,400 bytes, or 2400 MiB | Explicit local interpretation of that label using Java units |
| Total container cap | 3200 MiB, no extra swap | Local 800 MiB allowance for native JVM memory, measured separately from heap |
| Java | Temurin 17.0.15+6, pinned ARM64 image | Local runtime; Mojang's version metadata requires Java 17 |
| CPU | 3 cores on Oracle A1, leaving one host core | Existing local test budget; Aternos' CPU quota is not published |
| View / simulation distance | 6 / 4 | Existing local benchmark settings, not claimed as Aternos defaults |
| Seed and actions | `20260904`, separate exploration lanes, return route and combat | Existing reproducible workload |
| Player admission | 8 | Test ceiling, not a selected capacity |
| Authentication and game mode | Offline operator bots, creative flight, loopback listener | Local test setup, not an Aternos product configuration |

The [Compose override](compose.vanilla.yml) pins the Java 17 ARM64 image. Mojang's [1.20.1 metadata](https://piston-meta.mojang.com/v1/packages/19f5ae58f9c31bd3b0923cb822e99e3162bd62ab/1.20.1.json) identifies the [official server JAR](https://piston-data.mojang.com/v1/objects/84194a2f286ef7c14ed7ce0090dba59902951553/server.jar), SHA-1 `84194a2f286ef7c14ed7ce0090dba59902951553`. The downloaded smoke-test JAR matches it. The runner records its SHA-256 and the effective settings in each case.

Vanilla has no Paper `/tps` or `/mspt` commands. The runner samples the native `time query gametime` tick counter and records query duration and midpoint time. TPS windows use the latest earlier sample at least 60 seconds away, normally covering 60 to 66 seconds. Only available windows ending during an action phase enter qualification. These windows can contain earlier connection work; a short first phase may have no complete one-minute window. Per-phase observed mean TPS and its actual measurement duration are also reported.

Tick-time measurements come from Vanilla's built-in Java Flight Recorder, using only `minecraft.ServerTickTime` events. These report an average tick duration about once per second. The p95 of those reported averages is not the p95 of individual ticks or the same metric as Paper's sampled five-second mean. [Mojang documents the native profiler](https://feedback.minecraft.net/hc/en-us/articles/4415128577293-Minecraft-Java-Edition-1-18).

The comparison keeps the numeric thresholds at minimum available one-minute TPS >=19 and p95 reported mean tick time <=50 ms in both repetitions. It reports connection, new-terrain, loaded-terrain and combat context so that a pass or failure is not presented as a universal player limit. The clients share the Oracle host; player Internet latency is outside this test.

The full run repeats 1, 2, 4 and 8 players twice, uses fresh worlds and verifies movement, player-attributed hits, save, clean stop and marker recovery. Host memory, free-disk and OOM guards remain active. Heap, process RSS and container memory are separate measurements.

Only the filtered native tick-event JSON is copied into the repository. Full JFR files remain on the test host because JVM recordings can contain environment variables. No `.env`, keys or world archives are part of the evidence export.

```sh
sudo python3 run.py vanilla-acceptance --host oracle --vanilla
python3 summarize.py evidence/vanilla-acceptance
```
