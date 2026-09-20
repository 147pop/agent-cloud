# TES-157 clean-machine platform reproduction evidence

Date: 2026-09-20

Tested commit: `7ac330d` (tip of the TES-156 branch; identical code lands on
`main` via PR #29). The journey and trials harnesses are
`infra/compose/journey.sh` and `infra/compose/trials.sh`, executed with the
documented commands (`--accept-eula --fresh`), generating random local
credentials that were never printed.

## Result matrix

| Platform | Journey | Trials | Notes |
| --- | --- | --- | --- |
| macOS arm64 (host) | PASS 89 s | PASS 121 s | Docker Engine 28.4.0, Compose 2.39.4-desktop.1 |
| Linux arm64 (Lima vz VM, Ubuntu 26.04, aarch64) | PASS 92 s | PASS 131 s | Docker Engine 29.8.1 (API 1.56), Compose v5.5.1, Node 22.20.0 |
| Linux amd64 workload via Rosetta (same vz VM, `DOCKER_DEFAULT_PLATFORM=linux/amd64`) | PASS 227 s | PASS 343 s | Real x86_64 binaries for every service (postgres, cloud-control, Paper JVM), translated by Rosetta binfmt |
| Linux amd64 (Lima QEMU x86_64 VM, Ubuntu 26.04) | FAIL | not attempted | JVM `SIGSEGV` inside `mc-image-helper` during the Paper install step under QEMU TCG emulation; the container restart-loops before Paper ever boots. Emulation limitation, not a product defect |

## Environment adaptations (recorded, none committed to the repo)

1. **Lima ships rootless-only dockerd.** The `docker` template runs the
   daemon as the unprivileged `lima` user with its socket at
   `/run/user/501/docker.sock`, while `compose.yaml` bind-mounts
   `/var/run/docker.sock` into `cloud-control`. Before the fix,
   `cloud-control` observed an empty rootful daemon, saw `game-1` as absent
   and logged `reconciliation_incomplete` every tick while `cloud-game-1`
   sat in `Created` on the rootless daemon. Resolution inside the VM:
   `systemctl unmask docker docker.socket containerd`, start `containerd`
   and `docker`, add `lima` to the `docker` group, `docker context use
   default`. On a stock Linux Docker install (rootful daemon at
   `/var/run/docker.sock`, user in `docker` group) none of this is needed.
2. **Digest-pinned images are stored per-platform.** After the arm64 pull,
   the local image index held only the arm64 variant, so an amd64 compose
   run failed with `does not provide the specified platform`. Resolution:
   `docker pull --platform linux/amd64 <image>@<digest>` for the two pinned
   images before `DOCKER_DEFAULT_PLATFORM=linux/amd64` compose up. On a
   native amd64 host `docker compose pull` fetches the right variant by
   itself.
3. **Rosetta binfmt ran the amd64 workload.** The vz VM registers
   `/mnt/lima-rosetta/rosetta` via binfmt_misc; setting
   `DOCKER_DEFAULT_PLATFORM=linux/amd64` made every build, pull and
   container linux/amd64 without editing `compose.yaml`.
4. **QEMU full-VM amd64 emulation is not a supported test path** on this
   hardware: the Temurin JVM crashes (`SIGSEGV`, core dumped in
   `mc-image-helper install-paper`) under TCG before Paper starts. Native
   amd64 hardware, CI runners, or translation layers (Rosetta/Apple
   Virtualization) are the viable amd64 environments.

## Reproduced acceptance flow (per passing platform)

First creation via REST, rejected second creation
(`409 capacity_unavailable`), REST/MCP/CLI status and lifecycle, Minecraft
protocol readiness (`Paper 26.2`, protocol 776, endpoint
`127.0.0.1:25565`), world-marker persistence across stop/start, typed
errors (`action_required`/`accept_eula`, `unauthorized`,
`idempotency_key_reused`), control restart mid-start and mid-stop
convergence, forced container recreation preserving world and endpoint,
single-writer invariants, and clean shutdown with named volumes preserved.

**Safe setup reapplication** was additionally exercised live on the macOS
host: re-running `infra/compose/setup.sh` over the existing installation
returned successfully as a no-op (no container recreation), and
`cloud-control` then converged `game-1` from its durable `running` desired
state; the world marker from the trials run survived intact.

## Resource notes

- Lima VMs: 4 vCPU / ~6 GiB / 20 GiB disk each; vz (arm64, native) and
  QEMU (amd64, emulated) templates.
- Under Rosetta the Paper boot reached `running` in ~95–126 s (vs ~30–42 s
  native arm64); the trials' fixed 300 s timeouts were sufficient.
- No credentials, host addresses, or operator identifiers are included.
