# E1: Paper on K3s as Spectrum origin

Operator runbook for the qualified `paper-e0-oracle` profile ([profile.json](../../../../benchmarks/minecraft/profile.json))
running as a K3s Deployment + PVC, reachable through Cloudflare Spectrum. Companion to the
Compose recipes in this catalog entry, which stay for local dev/smoke testing — this is the
real-host path.

## Prerequisites (not done by this runbook)

- K3s installed on `control-1` (server) and `game-1` (agent). No installer exists in this repo yet.
- `game-1` labeled to match `nodeSelector` in [deployment.yaml](deployment.yaml)
  (`cloud.example/role: game` — update both if the operator picks a different label).
- Cloudflare Spectrum application created, origin pointed at `game-1`'s host IP, port 25565.

## Apply order

```sh
kubectl apply -f namespace.yaml
kubectl apply -f storageclass.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl -n cloud-minecraft-paper get pods -w
```

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
| 6 | Node-loss/recovery drill | Isolate `game-1`; restore latest R2 backup onto a new PVC on a temporary second worker | Exercises the recovery flow in [architecture.md](../../../../docs/architecture.md) (the D8 exercise) |

## Verification per scenario

- `sha256sum` on `level.dat` and region files, before and after.
- `kubectl logs -n cloud-minecraft-paper <pod>` grepped for lock-acquisition or corruption
  signatures (e.g. `Unable to access world`, `session.lock`).
- `mc-monitor status --host <origin-ip> --port 25565` (bundled in the itzg image) after
  replacement, to confirm a single healthy instance answers.
- One manual check: place a block, restart via the scenario's command, confirm the block persists
  and no `CrashLoopBackOff` occurred outside scenario 3/4's expected race window.

## Out of scope here

Bootstrapping K3s, labeling `game-1`, applying these manifests, creating the Spectrum origin
binding, and running the six scenarios against real hosts all need operator hands-on access and
happen outside this repo change. Once evidence exists, update
[architecture.md](../../../../docs/architecture.md) and
[decisions.md](../../../../docs/decisions.md) (D5) per their pending-validation notes.
