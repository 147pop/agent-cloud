# Free-profile results

Status: `Qualified` for E1, accepted by Pablo on 2026-09-06. The selected profile is Paper 26.2 build 121, one active instance with two players on the tested Oracle A1 host. Pablo accepted the repeated bot activity and local recovery evidence for [TES-144](https://linear.app/workspace/issue/TES-144) and [TES-140](https://linear.app/workspace/issue/TES-140). This replaces the earlier requirement for a human session before selecting the profile.

The accepted recipe uses two CPU quota units, a 2 GiB heap, a 3 GiB container limit, `ActiveProcessorCount=2`, view distance 6, simulation distance 4 and seed 20260904. It adds no gameplay plugins. The [method](free-profile.md), [pinned profile](free-profile.json) and [retained attempts](evidence/free/README.md) define the tested conditions. K3s lifecycle acceptance remains separate. Authenticated external play and Cloudflare Spectrum are untested; Spectrum implementation and route validation move to the final gate before public opening in [TES-18](https://linear.app/workspace/issue/TES-18).

## Controlled comparison

Both engines passed two repetitions with two nearby synthetic players, using lanes 32 blocks apart. Each repetition completed fresh and populated worlds, verified actions, clean backup and restoration into empty world paths, and recovery of the marker and 32 persistent entities after restart.

| Engine | Minimum minute TPS | Worst sampled tick p95 | Worst sampled tick p99 | Peak game memory | Mean active CPU cores | Result |
| --- | --- | --- | --- | --- | --- | --- |
| [Paper 26.2 build 121](evidence/free/compare-paper/measurements.json) | 19.42 | 23.1 ms | 59.7 ms | 2729 MiB | 0.424 | Passed both repetitions |
| [Fabric, Lithium and FerriteCore](evidence/free/compare-fabric-v2/measurements.json) | 19.99 | 29.4 ms | 914.3 ms | 2065 MiB | 0.447 | Passed both repetitions |

Tick percentiles are the worst native 100-tick windows sampled during the active phases. They are not percentiles over the entire run. Memory is the highest container sample across the battery. CPU is the duration-weighted mean of the four active phase measurements. These two repetitions do not establish a general engine ranking.

Paper was selected for the separate-terrain and density checks. It had the lower tick tail, comparable CPU use and a memory peak within the fixed 3 GiB container budget. Fabric remains an alternative; its lower observed memory use does not by itself increase the tested host capacity. C2ME has not been enabled because the nearby-player comparison did not show generation waits requiring it.

## Separate player routes

Paper passed [two repetitions with lanes 256 blocks apart](evidence/free/candidate-paper-spread/measurements.json). Both fresh and populated phases passed, including backup, restoration, restart and recovery of the marker and all 32 persistent entities.

| Measurement | Observed value |
| --- | --- |
| Minimum minute TPS | 19.06 |
| Worst sampled tick p95 / p99 | 26.7 / 125.9 ms |
| Maximum chunk wait | 3.502 s |
| Peak game memory, including startup | 2768 MiB |
| Mean active CPU | 0.577 cores |
| Maximum readiness time | 50.79 s |
| Largest populated world | 28.49 MB |

The minimum TPS was close to the 19 TPS screening cut. Each player flew 480 blocks out and back, fought mobs and completed the short Survival checks. This result covers one instance. The density study below uses the same separated lanes with `--seconds 120`, doubling the route length.

## Concurrent instances

The repeated screening pass is one Paper instance with two synthetic players. Each player travelled 960 blocks out and back on lanes 256 blocks apart. Two instances did not pass the control-response rule. These are the tested outcomes; they do not establish the host's physical maximum or a public offer.

| Instances x players | Minimum minute TPS | Worst sampled tick p95 / p99 | Maximum RCON observation | Peak game memory | Result |
| --- | --- | --- | --- | --- | --- |
| [1 x 2](evidence/free/density-paper-1/measurements.json) | 19.17 | 42.6 / 160.4 ms | 0.722 s | 2785 MiB | Both repetitions and all recovery checks passed |
| [2 x 2](evidence/free/density-paper-2/measurements.json) | 19.18 | 49.4 / 436.9 ms | 2.174 s | 5552 MiB, summed | Failed the RCON cut; stopped during the first repetition |

Performance values cover completed player phases. Memory covers all recorded samples, including startup. The passing level completed four active phases totalling 21.66 minutes. Both fresh backups restored into empty world paths with 84 matching files each, and both populated restarts recovered the marker and all 32 persistent entities.

At the passing level, mean active game CPU was 0.486 cores, peak observed host busy CPU was 2.94 cores, and available host memory stayed above 19.98 GiB. Free disk stayed above 33.11 GiB. The largest world reached 40.40 MB and the slowest readiness check took 50.75 seconds.

The [two-instance attempt](evidence/free/density-paper-2/measurements.json) completed both fresh-world scenarios, with two players per instance and 297 continuous seconds of simultaneous play. The largest client command wait was 22 ms. Tick and client-command measurements passed their limits.

One RCON gametime observation took 2.174 seconds, exceeding the predeclared two-second maximum. It began during that instance's `save-all flush` and returned as the save completed. The save took 2.725 seconds. The RCON timing includes launching `docker exec` and running the query. It does not isolate a game-thread stall, so this failure alone cannot establish poor player experience or the host's physical capacity.

The [operator stop record](evidence/free/density-paper-2/operator-stop.json) preserves the completed measurements and reason for stopping. The runner stopped during the populated phases after the fresh-world failure was confirmed. It did not finish those phases or the second repetition. Both fresh backups had been restored and checked, but the full populated restart cycle was not completed at this level.

Peak game-container memory summed to 5552 MiB, peak observed host busy CPU was 3.93 cores, and minimum available host memory was 17.37 GiB. Samples captured another instance starting during play, a save during play and a background save while another instance was playing. No memory or disk safety reserve was crossed.

The [profile](free-profile.json) records the accepted E1 limit of one instance with two players and identifies its synthetic evidence. Two instances remain a failed level. C2ME remains untested; the two-instance failure concerned a control response during a save.

## TPS by player activity

These values come from the passing `density-paper-1` run, with two active bots in each world. Each bot flew 960 blocks out and 960 blocks back at height 300, in parallel lanes 256 blocks apart. Server responses confirmed both endpoints. Both bots fought mobs, then dug, placed a block and walked 12.7 to 12.9 blocks in Survival. Every completed scenario recorded at least 113 attributed combat hits per bot. The clients were active throughout the exploration and combat phases.

| World | Activity | Minimum minute TPS, repetition 1 | Minimum minute TPS, repetition 2 |
| --- | --- | --- | --- |
| Fresh | New terrain | 19.39 | 19.32 |
| Fresh | Return over loaded terrain | 19.99 | 19.99 |
| Fresh | Combat | 19.99 | 19.99 |
| Restored and populated | Outward route | 19.17 | 19.18 |
| Restored and populated | Return route | 19.99 | 19.99 |
| Restored and populated | Combat | 19.99 | 19.99 |

The populated world reuses the saved routes and adds 32 persistent entities and 16 hoppers. Its outward trip is not a second fresh-terrain test. Survival checks lasted about 5.5 seconds, so they have no separate one-minute TPS result. Four or eight players in one instance were not tested with this recipe.

The table uses native gametime deltas from [metrics.jsonl](evidence/free/density-paper-1/metrics.jsonl) and phase boundaries from the four `r*-i1-*-players.jsonl` files in [the same run](evidence/free/density-paper-1/). Select each case, world stage and activity by its query midpoint timestamp, then use [tick_windows](summarize.py) on those samples. Each window must fit entirely inside the activity. The retained windows span 61.26 to 62.01 seconds, with 6 to 8 windows per route and 12 per combat phase. TPS is capped at 20 and rounded only for display. The raw files and their checksums are unchanged.

## Provenance and recovery

The Paper comparison used the first committed runner. Fabric used the same player script, versions, resource limits and game configuration, with the later persistence preparation check for chunks unloaded after client disconnect. The [method](free-profile.md#bot-protocol-correction) records the correction and the retained failed attempt.

Fabric generates a small launcher JAR at startup. Its two repetitions produced different raw hashes because ZIP entry timestamps differed. Both JARs contained exactly the same two entries and identical entry bytes. The exported launcher snapshots match the raw hashes recorded before player actions. The report retains `raw_recipe_hashes_match: false` and compares the validated launcher contents; all other JAR and configuration hashes match directly. The actual game JAR is not exempted from byte comparison.

Every formal attempt archives its runtime sources and records their SHA-256 values. The derived measurements identify the reporting code separately. Export checksums cover the retained logs, metrics, configuration, source archives and generated launcher snapshots. World files and backup archives remain on the authorized host.

The recovery checks cover a local clean backup and restoration of these generated worlds. They do not close the platform's future R2 storage or recovery on another worker. The owner accepted this bounded bot workload for profile selection. Long human sessions, technical farms, client authentication and the Internet route remain outside the measured result. External connection, play and reconnect through Spectrum must be recorded before public opening in [TES-18](https://linear.app/workspace/issue/TES-18).
