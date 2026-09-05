# TES-51 worker disks

## Contabo

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

## Oracle Santiago

The same method ran on `game-host`, `203.0.113.11`, on 2026-09-05 after Docker preparation and before Paper. Its ext4 filesystem on `/dev/sda1` had 43.38 GiB free after the test. The temporary file was removed, and all 1024 operations completed. The [Oracle measurements](disk-oracle-20260905.json) preserve the exact timestamp, mount options and per-operation latencies.

| Phase | Paced throughput, MiB/s | Median latency, ms | p95 latency, ms |
| --- | ---: | ---: | ---: |
| Sequential write | 39.22 | 5.401 | 5.880 |
| Sequential read | 42.73 | 3.293 | 3.601 |
| Random write | 0.364 | 0.642 | 0.796 |
| Random read | 0.366 | 0.578 | 0.737 |

These results and the free space support the bounded Paper benchmark on Oracle. Its direct reads were slower than Contabo's in this probe; synchronous write latency was more consistent. Neither test measures saturation throughput. Oracle had no protected application endpoint, so its explicit host selection omits that probe:

```sh
sudo ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json --host oracle
```
