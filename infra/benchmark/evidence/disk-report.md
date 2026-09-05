# TES-51: Contabo disk

Measured on `control-host`, `203.0.113.12`, at `2026-09-05T02:07:58Z`. The tested filesystem was ext4 on `/dev/sda1`, mounted at `/`. It had 74.27 GiB free before and after the test, allowing for filesystem metadata changes.

The test used a temporary 256 MiB file, direct synchronous I/O and one outstanding operation. Each phase ran 256 operations. Sequential phases paused 20 ms between 1 MiB operations; random phases paused 10 ms between 4 KiB operations. `ionice -c3` and `nice -n 19` gave existing work priority. No caches were dropped and no raw device was written.

| Phase | Paced throughput, MiB/s | Median latency, ms | p95 latency, ms |
|---|---:|---:|---:|
| Sequential write | 36.13 | 2.885 | 13.419 |
| Sequential read | 45.51 | 0.911 | 1.414 |
| Random write | 0.346 | 0.651 | 1.327 |
| Random read | 0.356 | 0.371 | 0.853 |

All 21 HTTP probes to the protected application returned 200. The slowest took 135 ms. The test file was removed. This supports running the bounded Paper benchmark on this worker. It does not establish peak disk throughput or the capacity of several concurrent servers.

Reproduce on the authorized host from the benchmark directory with a new output name:

```sh
ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json
```

The [raw measurements](disk-20260905.json) contain every operation's latency, the filesystem, free space, file size, seed and HTTP timings. The [script](../disk.py) is the runnable measurement and includes a percentile self-check.
