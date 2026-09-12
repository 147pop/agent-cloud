# TES-69 Kubernetes runtime evidence

The two-host operator campaign ran on 2026-09-12 with K3s `v1.36.4+k3s1`.
The control service ran on `control-1`; managed Paper ran on `game-1`.
The application was built from clean commit `a2090b7d31b56ea2abccda23ae04b6005c1e439d`
on the control host. Its image was `cloud-control:tes-69-a2090b7`, with observed
container image ID
`sha256:0ad2d2ee6fe29bb8c543174c5b152b1dae0808aadf647e32fdc23daceaf77912`.
The final operator probe source was `f1186be`.

The deployment backed up PostgreSQL and the previous control manifest before
applying migration 3 and enabling reconciliation. It reused the scoped service
account from TES-64 and installed the catalog's `local-path-retain` StorageClass.
The application image includes the pinned Paper recipe; it does not download
a new recipe at runtime.

## Verified behavior

The first complete run created a new server while restarting the control
process, replayed its mutation key, wrote a Minecraft storage marker, restarted
the control again, stopped Paper and started the same logical server. It
preserved the world marker and the Deployment, Service, PVC and PV UIDs.
The control restart while Paper was running preserved the Paper Pod UID.
Paper stopped with exit code 0. Create including a control restart took 68.436
seconds, stop took 5.481 seconds, and restart took 36.827 seconds.

The final campaign passed Minecraft protocol requests through the logical
server's Service before and after restart. Create including the control
restart took 65.511 seconds, stop took 5.019 seconds, and restart took 34.529
seconds. Both control restarts preserved resource identities and world data.

The interrupted replacement also passed: the operator paused Java and
requested ordinary Pod deletion. Nine observations found the replacement
Pending without a container while the old Java process remained alive. After
resuming Java, the old container exited with code 0 before the new container
started. Shutdown including the pause took 22.782 seconds. The replacement
had zero restarts and preserved the marker. The probe installs a timed resume
fallback in case the operator connection is lost.

The probe checks that Paper has no service-account token, that repeated create
effects preserve existing replicas, and that stop retains the Service and
volume. Each run leaves its uniquely named logical server stopped, retains its
world, and restores the reference `paper-e0-oracle` deployment. Its marker is
removed only after a successful restart read.

## Reproduction

Use a clean checkout on `control-1` with the existing protected two-host
configuration and a database backup. Build/import the control image and enable
`CLOUD_RUNTIME=kubernetes` in the control Deployment. The regular
[two-host installer](../two-host/README.md) applies the runtime setting and
retained StorageClass. The reference server must have no players and the
managed worker slot must be empty before this probe starts.

From the repository root, as the operator with administrative K3s access:

```sh
set -eu
umask 077
mkdir -p infra/.local/tes-69
python3 infra/two-host/verify-kubernetes.py > infra/.local/tes-69/result.jsonl
```

[verify-kubernetes.py](../two-host/verify-kubernetes.py) drives the production
store inside the control Pod using
[verify-kubernetes.mjs](../two-host/verify-kubernetes.mjs). Credentials come
from that Pod's existing environment and projected service account. The
operator separately performs control restarts and Minecraft console checks.
Raw watches and fixture identifiers stay in private temporary directories.

The shared interruption and shutdown probes accept `CLOUD_VERIFY_DEPLOYMENT`
and `CLOUD_VERIFY_SELECTOR` for a managed workload. Without those variables,
their original reference-workload behavior is unchanged.

## Supporting checks and limits

- `npm run check`: 9 unit tests passed.
- PostgreSQL 17.6 `npm run test:integration`: 24 tests passed, including the
  12 process-kill scenarios from TES-71.
- `bash infra/two-host/test.sh`: passed.
- `python3 benchmarks/minecraft/summarize.py --self-test`: passed.
- Benchmark package manifests and lockfile unchanged; `git diff --check` passed.
- Production Docker build, image import and control rollout: passed.

TES-69 returns an internal Service endpoint. Stable external NodePorts belong
to TES-77. Bounded allocation, storage admission, REST/MCP/CLI and the full
external agent-to-play acceptance remain F3/F4 work. These runs preserve
Minecraft's existing authentication setting; they do not establish an
authenticated human gameplay session. A retained 10 GiB PVC is an allocation
request, not an enforced filesystem quota. Forced deletion and loss of the
worker node are outside this interrupted-replacement proof.
