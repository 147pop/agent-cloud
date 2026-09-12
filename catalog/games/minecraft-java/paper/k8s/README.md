# Paper lifecycle on K3s

Operator runbook for the accepted [free Paper profile](../../../../../benchmarks/minecraft/free-profile.json), running as a K3s Deployment with a retained PVC. The resource names retain `paper-e0-oracle`; the game settings now match the accepted 26.2 build 121 profile with two players, two CPU quota units, a 2 GiB heap and a 3 GiB total container RAM limit.

The benchmark used Docker with CPU affinity, loopback clients, offline operator identities and private RCON. This manifest uses Kubernetes scheduling and disables RCON. Foundation acceptance must validate the deployed limits and lifecycle; accepting the benchmark does not prove those Kubernetes checks. Spectrum is a final public-opening gate and is not a prerequisite for this runbook.

Scenarios 1 through 5 below cover lifecycle checks on the two-host foundation. Scenario 6 belongs to the later managed recovery stage and requires a temporary second game worker and R2. These manifests are inputs to the foundation; they do not implement its control API or warm-instance allocation.

## Prerequisites (not done by this runbook)

- K3s installed on `control-1` (server) and `game-1` (agent), via [the installer](../../../../../infra/k3s/).
- `game-1` labeled to match `nodeSelector` in [deployment.yaml](deployment.yaml)
  (`cloud.example/role: game` — update both if the operator picks a different label).
- A controlled operator or test-player connection to the Minecraft port. Record the path used for the lifecycle checks.

## Apply order

```sh
kubectl apply -f namespace.yaml
kubectl apply -f storageclass.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl -n cloud-minecraft-paper get pods -w
```

## Startup and readiness

The container uses the bundled `mc-monitor` binary for both Kubernetes probes.
A successful TCP connection is not enough: the Pod remains unready until
`mc-monitor status --host 127.0.0.1 --port 25565` completes a Minecraft status
request successfully.

The startup probe allows up to ten minutes for a cold Paper start and prevents
the readiness probe from running during that window. After startup succeeds,
the readiness probe repeats the protocol check every ten seconds and removes
the Pod from ready endpoints after three consecutive failures. There is no
liveness probe in this manifest; TES-62 does not add a restart policy for a
server that becomes unavailable after startup.

For a cold-start check, watch the Pod from creation through readiness and record
its restart count. `Ready` must remain false before the first successful
`mc-monitor` result, become true afterward, and the container must not restart
during an otherwise healthy slow start.

## Writer-lock mechanism under test

Five independent layers prevent two processes from writing the same world:

1. `strategy: Recreate` + `terminationGracePeriodSeconds: 120` — old Pod fully terminates
   (itzg image traps SIGTERM, saves world) before a replacement starts.
2. PVC on the `local-path-retain` StorageClass ([storageclass.yaml](storageclass.yaml):
   `rancher.io/local-path` provisioner, `reclaimPolicy: Retain`, `volumeBindingMode:
   WaitForFirstConsumer`), `ReadWriteOnce` — the PV binds to whichever node the first Pod lands
   on and carries that node's affinity from then on, so any replacement Pod using the same PVC is
   forced onto the same node/filesystem instance; `Retain` also means scaling to zero can never
   delete the world.
3. Backstop: Minecraft's own `world/session.lock` exclusive file lock — if timing ever races, the
   second process fails to acquire the lock and crashes loudly instead of corrupting data.
4. `hostPort: 25565` — the OS refuses a second bind to the same host port on `game-1`.
5. A dedicated `ServiceAccount` ([serviceaccount.yaml](serviceaccount.yaml)) with no RoleBinding
   and `automountServiceAccountToken: false` — not a writer-lock layer itself, but keeps a
   compromised or buggy container from reaching the Kubernetes API to force a second replica.

The scenarios below exercise interrupted stops and replacement to confirm these hold.

## Test scenarios

| # | Scenario | Command | Expected safe outcome |
| --- | --- | --- | --- |
| 1 | Clean scale down/up | `kubectl scale deploy/paper-e0-oracle -n cloud-minecraft-paper --replicas=0`, then `--replicas=1` | Old Pod saves & exits within the grace period; new Pod starts clean |
| 2 | Ordinary delete | `kubectl delete pod <pod> -n cloud-minecraft-paper` | `Recreate` replaces after full termination; no lock conflict |
| 3 | Immediate scale race | `--replicas=0` then `--replicas=1` back-to-back, no wait | Replacement forced to the same node (PVC affinity); if the old process hasn't released the lock, the new container fails to acquire it and CrashLoopBackOffs — must not write |
| 4 | Forced delete | `kubectl delete pod <pod> -n cloud-minecraft-paper --grace-period=0 --force` | Replacement still can't dual-write (`session.lock` backstop) |
| 5 | Delete mid-startup | Delete the Pod before the world fully loads | Clean replacement once the prior Pod is confirmed gone |
| 6 | Node-loss/recovery drill | Isolate `game-1`; restore latest R2 backup onto a new PVC on a temporary second worker | Exercises the recovery flow in [architecture.md](../../../../../docs/architecture.md) (the D8 exercise) |

## Verification per scenario

- `sha256sum` on `level.dat` and region files, before and after.
- `kubectl logs -n cloud-minecraft-paper <pod>` grepped for lock-acquisition or corruption
  signatures (e.g. `Unable to access world`, `session.lock`).
- `mc-monitor status --host <origin-ip> --port 25565` (bundled in the itzg image) after
  replacement, to confirm a single healthy instance answers.
- One manual check: place a block, restart via the scenario's command, confirm the block persists
  and no `CrashLoopBackOff` occurred outside scenario 3/4's expected race window.

## Out of scope here

Applying these manifests and running the lifecycle scenarios require evidence from the authorized hosts. Record the two-host lifecycle evidence in [TES-28](https://linear.app/workspace/issue/TES-28) and [TES-7](https://linear.app/workspace/issue/TES-7). [TES-18](https://linear.app/workspace/issue/TES-18) tracks Spectrum configuration, authenticated external play and reconnect after the functional invited beta, before public opening. See [the decision](../../../../../docs/decisions.md#d5-public-game-tcp-and-worker-ip-exposure-updated-2026-09-06).
