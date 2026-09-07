# TES-146 clean-clone quickstart design

## Context

TES-146 requires the selected two-host foundation to be reproducible from the
repository. The existing TES-151 implementation supplies the K3s installers,
rendering, deployment, verification and an operator-oriented runbook. TES-150,
TES-151 and TES-25 are complete; TES-152 is the remaining child deliverable.

The outstanding work is to make the installation path understandable and
reconstructible for a contributor starting from a clean clone, while keeping
operator secrets and host-specific evidence outside Git. F2/F3 lifecycle
operations and TES-148 acceptance are explicitly out of scope.

## Options considered

1. Extend `infra/two-host/README.md` into the canonical clean-clone quickstart
   and add small documentation gates to the existing test. This keeps one
   source of truth and minimizes divergence.
2. Add a separate `docs/two-host-quickstart.md` for contributors while keeping
   the current infrastructure README as an operator runbook. This separates
   audiences but duplicates setup concepts and creates a synchronization cost.
3. Generate the guide from a template and configuration metadata. This could
   reduce future repetition, but adds tooling without being needed for the
   current installation gate.

Option 1 is selected because the current scripts and runbook already form a
coherent installation surface; the missing work is audience, sequencing and
evidence clarity rather than a second configuration system.

## Design

### Canonical installation guide

Rewrite `infra/two-host/README.md` as a complete clean-clone quickstart. It
will document:

- the Ubuntu 24.04/systemd host contract, architecture, CPU, RAM, disk and
  required commands for `control-1` and `game-1`;
- the two-host trust boundary and the three distinct game address roles;
- cloning and selecting a verified commit;
- creating protected, ignored configuration with operator-owned credentials;
- explicit Minecraft EULA acceptance;
- host preparation, pinned K3s installation, join-token handling and firewall
  setup;
- deployment and readiness checks, including direct game TCP reachability and
  private PostgreSQL/K3s administration;
- a non-destructive second application of the setup that preserves world and
  database data;
- resource semantics: 2 GiB Java heap, 3 GiB total container memory, 10 GiB
  PVC/storage budget, filesystem reserve and worker reserve;
- troubleshooting and the installation boundary versus F2/F3 operations.

The guide will never include real addresses, SSH destinations, passwords,
machine tokens, join tokens or raw operator logs. It will use the existing
documentation values from `config.example.env` and explicitly instruct each
operator to substitute their own values.

### Repository entry points and gates

Update `README.md` and `infra/README.md` to point contributors to the
canonical quickstart. Extend `infra/two-host/test.sh` only with static gates
that protect TES-152 documentation invariants and relative links; it will not
attempt to install K3s or require access to live hosts.

Add `infra/evidence/tes-152-clean-clone-quickstart.md` containing the verified
source commit, reproducible local commands and their results. It will explain
which two-host results are recorded in the separate TES-151 evidence and which
operational details are intentionally kept in ignored local files.

### Verification

The implementation will run:

```text
bash infra/two-host/test.sh
for script in infra/k3s/*.sh infra/two-host/*.sh; do bash -n "$script"; done
npm run check
python3 benchmarks/minecraft/summarize.py --self-test
```

The final review will also inspect the changed-file list, links, secret
exposure and the clean worktree. Live two-host installation is not repeated in
this local change; the guide will preserve the commands and evidence boundary
needed for an operator to reproduce it on compatible hosts.

## Acceptance mapping

- Clean clone builds from the root: covered by the root commands and `npm run
  check` evidence.
- Compatible two-host setup: covered by host requirements, ordered commands,
  config semantics and the existing deployment/verification scripts.
- Operator credentials and EULA: covered by protected local config and the
  explicit `MINECRAFT_EULA=TRUE` gate.
- Repeat setup preserves durable data: covered by the second-pass procedure
  and the TES-151 installation evidence reference.
- Versions, requirements and commands: covered by the quickstart and evidence
  record without private operational values.
