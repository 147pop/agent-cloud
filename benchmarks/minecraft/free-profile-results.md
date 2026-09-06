# Free-profile results

Status: `Experimental`. [TES-140](https://linear.app/workspace/issue/TES-140) requires the controlled comparison, concurrent instances, persistence and external human play. The public player route and human session remain pending. The [method](free-profile.md), [pinned profile](free-profile.json) and [retained attempts](evidence/free/README.md) define the evidence boundary.

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

The minimum TPS was close to the 19 TPS screening cut. Each player flew 480 blocks out and back, fought mobs and completed the short Survival checks. This result covers one instance. The density study uses the same separated lanes with `--seconds 120`, doubling the route length, before recording a concurrent-instance boundary.

## Concurrent instances

The [two-instance attempt](evidence/free/density-paper-2/measurements.json) did not pass. Both fresh-world scenarios completed, with two players per instance and 297 continuous seconds of simultaneous play. The minimum minute TPS was 19.18, the worst sampled tick p95 was 49.4 ms, and the largest client command wait was 22 ms. Those measurements passed their limits.

One RCON gametime observation took 2.174 seconds, exceeding the predeclared two-second maximum. That duration includes launching `docker exec` and running the query. It does not isolate a game-thread stall, so this failure alone cannot establish poor player experience or the host's physical capacity.

The [operator stop record](evidence/free/density-paper-2/operator-stop.json) preserves the completed measurements and reason for stopping. The runner stopped during the populated phases after the fresh-world failure was confirmed. It did not finish those phases or the second repetition. Both fresh backups had been restored and checked, but the full populated restart cycle was not completed at this level.

Peak game-container memory summed to 5552 MiB, peak observed host busy CPU was 3.93 cores, and minimum available host memory was 17.37 GiB. Samples captured another instance starting during play, a save during play and a background save while another instance was playing. No memory or disk safety reserve was crossed.

One instance is now being repeated with the same longer workload. The earlier short-route pass cannot substitute for that check. No concurrent-instance count from this density study is accepted yet.

## Provenance and recovery

The Paper comparison used the first committed runner. Fabric used the same player script, versions, resource limits and game configuration, with the later persistence preparation check for chunks unloaded after client disconnect. The [method](free-profile.md#bot-protocol-correction) records the correction and the retained failed attempt.

Fabric generates a small launcher JAR at startup. Its two repetitions produced different raw hashes because ZIP entry timestamps differed. Both JARs contained exactly the same two entries and identical entry bytes. The exported launcher snapshots match the raw hashes recorded before player actions. The report retains `raw_recipe_hashes_match: false` and compares the validated launcher contents; all other JAR and configuration hashes match directly. The actual game JAR is not exempted from byte comparison.

Every formal attempt archives its runtime sources and records their SHA-256 values. The derived measurements identify the reporting code separately. Export checksums cover the retained logs, metrics, configuration, source archives and generated launcher snapshots. World files and backup archives remain on the authorized host.

The recovery checks cover a local clean backup and restoration of these generated worlds. They do not close the platform's future R2 storage or recovery on another worker. Ordinary play, client authentication and the proposed Internet route belong to [TES-144](https://linear.app/workspace/issue/TES-144).
