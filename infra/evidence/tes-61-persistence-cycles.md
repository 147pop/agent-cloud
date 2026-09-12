# TES-61: twenty persistence cycles and interrupted termination

On 2026-09-12 UTC, all twenty complete cycles preserved a unique Minecraft
command-storage value on the real `game-1` worker. Every old container exited
with code `0` inside the 120-second grace period. Every replacement became
protocol-ready with zero container restarts.

## Fixed inputs and reproduction

The tests used K3s `v1.36.4+k3s1` on both hosts and Paper `26.2`, build `121`,
with the pinned image
`itzg/minecraft-server@sha256:efa878ddb49cf5251b2e5f2ad71b08fd2f7236c1f7907433f6697258b31d2ce4`.
The workload retained its original world PVC, one replica, two CPUs, `3Gi`
container memory, `2G` heap and `hostPort: 25565` throughout the trials.

The twenty-cycle probe was the unchanged TES-57 source at `58f86bb`, now
merged through PR #14. The final interruption probe ran from a clean Git
bundle clone at `cfc9d95`. From the repository root on `control-1`, as root:

```bash
set -euo pipefail
umask 077
mkdir -p infra/.local/tes-61
for cycle in {1..20}; do
  python3 infra/two-host/verify-shutdown.py \
    | tee "infra/.local/tes-61/cycle-$cycle.json"
done
python3 infra/two-host/verify-interruption.py \
  | tee infra/.local/tes-61/interruption.json
```

Each probe checks zero connected players before modifying state. The cycle
probe writes a fresh value through Minecraft's private console, verifies it,
stops the server, records the exit, starts a replacement, reads the value and
removes its own value. Raw Pod watches, logs and JSON results remain private
because they contain host details.

## Twenty-cycle results

| Measurement | Minimum | Maximum | Mean |
| --- | --- | --- | --- |
| Clean shutdown | 1.794 s | 3.722 s | 2.183 s |
| Replacement readiness and persisted-value read | 34.573 s | 36.017 s | 35.295 s |

All twenty results reported `passed`, `exit_code: 0`,
`world_marker: preserved` and the selected two-CPU/3Gi limits. Restart timing
includes the rollout and console read. These are existing-world restart
measurements, not cold/warm allocation or authenticated player-login timings.

## Interrupted termination and replacement

The final probe paused the old Java process, requested ordinary Pod deletion
and kept observing both Pods for twenty seconds. Across eleven observations,
the old Java process remained paused and alive, while the replacement stayed
Pending without a started container. The scheduler reported that the game
node's requested host port was occupied; the control node was excluded by its
taint.

After resuming Java, the old container saved the world and exited with code
`0`. Total shutdown, including the deliberate pause, was **24.904 seconds**.
The recorded replacement-container start timestamp was strictly later than
the old container's termination timestamp. The replacement had zero restarts
and returned the same unique Minecraft value, which the probe then removed.

An earlier run passed the same interruption scenario in 24.674 seconds. The
final source adds an explicit assertion over the two container timestamps;
the clean-clone run above passed that stronger check.

This proves exclusion for ordinary Pod deletion with the fixed host port.
`Recreate` and `ReadWriteOnce` alone do not guarantee exclusion for every
replacement path. Force deletion, node loss, a different endpoint design and
the future control-runtime adapter require their own checks.

## Resource and storage boundary

The final replacement's cgroup reported `cpu.max = 200000 100000` (two CPUs)
and `memory.max = 3221225472` (3 GiB). The worker has four CPUs and
25,139,412,992 bytes of physical memory; the observed available memory was
22,426,779,648 bytes. The selected instance leaves the planned two-CPU and
4-GiB host reserve.

The PVC requests 10 GiB. It is a retained static local volume on the host
filesystem, whose available space was 33,124,110,336 bytes at capture. The
10-GiB request is an allocation budget, not a filesystem quota. The 10-GiB
free-disk reserve and actual disk accounting remain separate from the 3-GiB
container RAM limit.

Python syntax validation, the live probes and final diff checks passed.
These results satisfy TES-61's fixed-worker lifecycle checks; F4 still needs
the control interfaces, admission, cold/warm allocation and full agent-to-play
journey.
