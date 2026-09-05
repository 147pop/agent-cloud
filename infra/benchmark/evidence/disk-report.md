# Disk results, 2026-09-05

Both disks completed the test with enough free space for the Minecraft benchmark. These paced rates do not measure maximum throughput or concurrent-server capacity.

| Measurement | Contabo | Oracle |
| --- | ---: | ---: |
| Sequential write, MiB/s | 36.13 | 39.22 |
| Sequential read, MiB/s | 45.51 | 42.73 |
| Random write, MiB/s | 0.346 | 0.364 |
| Random read, MiB/s | 0.356 | 0.366 |
| Sequential write p95, ms | 13.419 | 5.880 |
| Sequential read p95, ms | 1.414 | 3.601 |
| Random write p95, ms | 1.327 | 0.796 |
| Random read p95, ms | 0.853 | 0.737 |
| Free disk after test, GiB | 74.27 | 43.38 |

Oracle's direct reads were slower in this probe; its synchronous write latency was more consistent.

## Method

| Parameter | Value |
| --- | --- |
| Filesystem | ext4 on `/dev/sda1`, mounted at `/`, both hosts |
| Test file | Temporary 256 MiB file, removed afterward |
| I/O | Direct synchronous, one outstanding operation |
| Operations | 256 per phase, 1024 completed per host |
| Sequential phase | 1 MiB operations, 20 ms pause |
| Random phase | 4 KiB operations, 10 ms pause |
| Priority | `ionice -c3`, `nice -n 19` |
| Salta protection | 21/21 HTTP 200, slowest 135 ms |

Throughput includes the pauses. The test did not drop caches or write to raw devices. Oracle has no protected application endpoint, so `--host oracle` omits that probe.

| Host | Measurement record |
| --- | --- |
| Contabo `control-host`, `203.0.113.12` | [02:07:58 UTC, raw measurements](disk-20260905.json) |
| Oracle `game-host`, `203.0.113.11` | [After Docker preparation, before Paper](disk-oracle-20260905.json) |

The raw records retain every latency, medians, filesystem details, timestamps and HTTP timings.

## Reproduce

From the benchmark directory on the authorized host, use a new output name.

Contabo:

```sh
ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json
```

Oracle:

```sh
sudo ionice -c3 nice -n 19 python3 disk.py evidence/disk-new.json --host oracle
```

[Measurement script](../disk.py) · [TES-51](https://linear.app/workspace/issue/TES-51)
