# TES-152 clean-clone quickstart evidence

This record verifies the repository entry points and the canonical
[two-host clean-clone quickstart](../two-host/README.md) against implementation
state `38cdd84` (`38cdd844b3e425b80fd9b8f10150ed8e841222dc`) on 2026-09-08. The
checks were run before this evidence-only documentation commit, so that commit
does not change the tested scripts, application or pinned deployment inputs.

## Installation boundary

The guide covers the F1 installation gate: a clean clone installs `control-1`
with the K3s server, PostgreSQL and `cloud-control`, and `game-1` with the K3s
agent, pinned Paper workload and persistent world. It documents readiness and
a non-destructive reapply using credentials owned by the operator.

It does not claim token enforcement, lifecycle operations, API/MCP/CLI
parity, allocation behavior or a playable endpoint. Those remain F2/F3 work,
and the complete journey is accepted separately by
[TES-148](https://linear.app/workspace/issue/TES-148/f4-accept-the-reproducible-two-host-minecraft-foundation).

No live reinstall was run for TES-152. The existing
[TES-151 live installation evidence](tes-151-two-host-installation.md) records
the two-host installation, readiness and persistence result. TES-152 verified
the public reproduction path and local checks without replacing that live
evidence.

## Compatible hosts

Both hosts require Ubuntu 24.04 with systemd, Git, Bash, `netcat-openbsd`
(`nc`), UFW, root access and private connectivity between the assigned host
addresses. The documented probes additionally use OpenSSL; the operator probe
machine needs `curl` and `nc`.

| Role | Architecture | Minimum capacity | Additional requirement |
| --- | --- | --- | --- |
| `control-1` | amd64 | 2 CPUs, 2 GiB RAM, 10 GiB free disk | Docker Engine and `curl` |
| `game-1` | arm64 | 4 CPUs, 7 GiB RAM, 20 GiB free disk | `curl` |

The `game-1` requirement separates the selected two-CPU workload from its
two-CPU host reserve, and the 2 GiB Java heap from the 3 GiB total container
RAM limit and 4 GiB host RAM reserve. The 10 GiB PVC request is an allocation
budget, not an enforced filesystem quota; the host also retains a 10 GiB free
disk reserve.

## Pinned inputs and private capture location

| Component | Expected input |
| --- | --- |
| K3s | `v1.36.4+k3s1` |
| Paper | `itzg/minecraft-server@sha256:efa878ddb49cf5251b2e5f2ad71b08fd2f7236c1f7907433f6697258b31d2ce4`, version `26.2`, build `121` |
| PostgreSQL | `postgres:17.6-bookworm@sha256:f3bd19c606e442c3d7bdfa8002e03fe260a1023351e0ea4598032022b68dd6e3` |
| `cloud-control` | local image `cloud-control:tes-151`, package `0.0.0`, Node `22.20.0-bookworm-slim@sha256:b21fe589dfbe5cc39365d0544b9be3f1f33f55f3c86c87a76ff65a02f8f5848e` in both Dockerfile stages |

The quickstart names the repository files that pin each value. The operator
captures the checked-out commit and installed K3s version separately on both
live hosts below ignored `infra/.local/tes-151-versions/`, transfers the
non-secret `game-1` captures to `control-1`, and compares each pair there.
After deployment, the operator uses Kubernetes from `control-1` to capture the
effective Paper image, version and build plus the PostgreSQL and
`cloud-control` image references, and uses K3s containerd on `control-1` to
capture the local `cloud-control` import record. These local captures are not
committed.

## Local verification results

The following exact commands passed at implementation state `38cdd84`:

```text
$ bash infra/two-host/test.sh
Rendered manifests in <temporary-directory>/rendered
two-host tests passed

$ for script in infra/k3s/*.sh infra/two-host/*.sh; do bash -n "$script" || exit 1; done
# exit 0; every K3s and two-host shell script passed Bash syntax validation

$ npm run check
# TypeScript build passed; tests 2, pass 2, fail 0

$ python3 benchmarks/minecraft/summarize.py --self-test
Metric parsing checks passed
```

`benchmarks/minecraft/package.json` and
`benchmarks/minecraft/package-lock.json` were unchanged from `38cdd84`.

## Reapply and persistence boundary

An ordinary reapply uses the same verified commit and protected configuration,
reruns the pinned installers, firewall and host preparation, then reruns
`deploy.sh` and `verify.sh`. It must not invoke `reset-host.sh`, delete PVCs or
delete the configured host data paths. The gate compares the before/after PVC
and PV identities, the same PostgreSQL probe row and the world-marker hash,
and requires every workload to return Ready. `reset-host.sh` remains an
explicitly destructive dedicated-host reset outside the normal reapply path.

No secrets, host addresses, SSH targets, provider identifiers or raw
operational logs are committed in this record. The guide uses documentation
addresses and operator-owned values, keeps sensitive and host-specific state
in ignored local paths, and can be followed without Linear access.
