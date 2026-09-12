# TES-57: clean Paper shutdown

On 2026-09-12 UTC, the fixed Paper workload on the two-host K3s installation
stopped with exit code `0` in **1.778 seconds**, below its 120-second grace
period. A replacement Pod became protocol-ready and returned the last
Minecraft command-storage value in **35.356 seconds**. The probe removed its
value after verification.

## Inputs and reproduction

- Probe source: `58f86bb`, a clean Git bundle clone on `control-1`.
- K3s on both nodes: `v1.36.4+k3s1`; both nodes Ready.
- Paper: version `26.2`, build `121`, image
  `itzg/minecraft-server@sha256:efa878ddb49cf5251b2e5f2ad71b08fd2f7236c1f7907433f6697258b31d2ce4`.
- Profile: two CPUs, `3Gi` container memory, `2G` heap, one replica, retained
  world PVC and `Recreate` strategy.
- `terminationGracePeriodSeconds: 120`, RCON disabled, private console pipe
  enabled by `CREATE_CONSOLE_IN_PIPE=true`.

From the repository root on `control-1`, after deploying the manifest:

```sh
sudo python3 infra/two-host/verify-shutdown.py
```

The existing installation received only the console-pipe environment setting
before this run. No world, PVC or namespace was deleted. There were zero
players connected when the probe started.

## Observed result

```json
{
  "result": "passed",
  "shutdown_seconds": 1.778,
  "restart_seconds": 35.356,
  "exit_code": 0,
  "world_marker": "preserved",
  "limits": {"cpu": "2", "memory": "3Gi"}
}
```

The Kubernetes Pod watch captured the terminated container with exit code
`0`. The runner log recorded graceful stopping, the Minecraft `stop` command,
world saving and successful completion. The replacement had a different Pod
UID and zero container restarts. `mc-monitor status` succeeded before the
Minecraft console read returned the persisted unique value.

The raw Pod watch and shutdown logs remain in the private directory reported
by the probe. They are not committed because Kubernetes records include host
details. `restart_seconds` includes rollout readiness and the storage read;
it is not a cold-allocation or player-login measurement.

## Verification and limits

`bash infra/two-host/test.sh`, Python syntax validation and `git diff --check`
passed. The first live attempt stopped before changing the world because the
console command requires the Minecraft user. The corrected probe uses the
image's bundled `gosu 1000:1000` and passed as recorded above.

This proves one clean shutdown and persistent Minecraft state for TES-57.
Twenty cycles, interrupted termination and writer exclusion belong to TES-61;
the full agent-to-play journey remains an F4 gate.
