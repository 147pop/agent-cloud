# TES-151 Two-Host Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Install pinned `cloud-control`, PostgreSQL and Paper workloads on a freshly rebuilt two-host K3s cluster and prove that an ordinary reapply preserves both data volumes.

**Architecture:** K3s runs all three workloads. Repository scripts load a validated, ignored environment file, render explicit local-volume manifests, build and import the `cloud-control` image, apply the resources and verify placement, readiness, networking and persistence without printing secrets.

**Tech Stack:** Bash, K3s/Kubernetes YAML, Docker, Node.js 22, TypeScript 7, PostgreSQL, Paper/itzg Minecraft image.

---

### Task 1: Define and test the deployment configuration contract

**Files:**
- Modify: `.gitignore`
- Create: `infra/two-host/config.example.env`
- Create: `infra/two-host/lib.sh`
- Create: `infra/two-host/test.sh`

**Step 1: Write failing configuration tests**

Create a shell test that sources `lib.sh` and checks:

- a complete temporary configuration is accepted;
- missing secrets are rejected without echoing their values;
- ports, CIDRs, node names, CPU/RAM/storage values and `/var/lib/cloud/...`
  data paths are validated;
- unsafe data paths such as `/`, `/var/lib` and a home directory are rejected.

**Step 2: Run the tests and confirm failure**

Run: `bash infra/two-host/test.sh`

Expected: FAIL because `lib.sh` and the configuration contract do not exist.

**Step 3: Implement minimal validated loading**

Add helpers that load a trusted operator-owned env file, require every input,
validate scalar formats and never print secret values. Add `infra/.local/` to
`.gitignore`. The example file contains placeholders for:

```sh
K3S_VERSION=v1.36.4+k3s1
CONTROL_NODE_NAME=control-1
GAME_NODE_NAME=game-1
CONTROL_PRIVATE_ADDRESS=192.0.2.10
GAME_PRIVATE_ADDRESS=192.0.2.20
CONTROL_API_CLIENT_CIDR=192.0.2.30/32
CONTROL_API_PORT=3000
GAME_PORT=25565
POSTGRES_DATA_PATH=/var/lib/cloud/tes-151/postgres
GAME_DATA_PATH=/var/lib/cloud/tes-151/minecraft
POSTGRES_STORAGE_GIB=10
GAME_STORAGE_GIB=10
GAME_CPU=2
GAME_JAVA_HEAP=2G
GAME_MEMORY=3Gi
GAME_HOST_RESERVED_CPU=2
GAME_HOST_RESERVED_MEMORY_GIB=4
GAME_HOST_RESERVED_DISK_GIB=10
POSTGRES_PASSWORD=replace-me
CLOUD_MACHINE_TOKEN=replace-me
```

Use documentation-only addresses and values in the checked-in example.

**Step 4: Run tests and syntax checks**

Run: `bash infra/two-host/test.sh && bash -n infra/two-host/*.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add .gitignore infra/two-host
git commit -m "build: define TES-151 deployment configuration"
```

### Task 2: Pin and harden the existing K3s bootstrap

**Files:**
- Modify: `infra/k3s/install-control.sh`
- Modify: `infra/k3s/install-game.sh`
- Modify: `infra/k3s/firewall-control.sh`
- Modify: `infra/k3s/firewall-game.sh`
- Modify: `infra/k3s/verify.sh`
- Modify: `infra/two-host/test.sh`

**Step 1: Add failing source-level tests**

Assert that both installers default to `v1.36.4+k3s1`, pass
`INSTALL_K3S_VERSION`, do not print the join token, and preserve environment
overrides. Assert that firewall scripts validate addresses/ports and create the
configured operator API and game TCP rules in addition to the private cluster
rules.

**Step 2: Run tests and confirm failure**

Run: `bash infra/two-host/test.sh`

Expected: FAIL against the channel-based installers and fixed firewall rules.

**Step 3: Implement pinned, idempotent bootstrap behavior**

Use the pinned version by default, report the resolved version, and report only
the path to the join token. Extend firewall scripts with explicit, validated
inputs while retaining the existing K3s restrictions. Extend `verify.sh` to fail
unless exactly one control role and one game role are Ready.

**Step 4: Run tests and shell syntax checks**

Run: `bash infra/two-host/test.sh && bash -n infra/k3s/*.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add infra/k3s infra/two-host/test.sh
git commit -m "fix: pin and validate the two-host K3s bootstrap"
```

### Task 3: Package `cloud-control` as a pinned container

**Files:**
- Create: `.dockerignore`
- Create: `apps/cloud-control/Dockerfile`
- Modify: `infra/two-host/test.sh`

**Step 1: Add failing package assertions**

Check that the Dockerfile uses an immutable Node base reference, builds with
`npm ci`, copies only runtime output into the final stage and runs as the
unprivileged `node` user.

**Step 2: Run the test and confirm failure**

Run: `bash infra/two-host/test.sh`

Expected: FAIL because the Dockerfile is absent.

**Step 3: Add the multi-stage Dockerfile**

Build the root workspace in the first stage and copy only
`apps/cloud-control/dist/src` to the runtime image. Keep build artifacts,
credentials, Git metadata, benchmark evidence and local operator files out of
the Docker context where they are not required.

**Step 4: Build and smoke-test the image**

Run on a Docker-capable amd64 host:

```bash
docker build -f apps/cloud-control/Dockerfile -t cloud-control:tes-151 .
docker run --rm --user node -e HOST=0.0.0.0 cloud-control:tes-151
```

Probe `/healthz` from a second command and stop the test container.

Expected: HTTP 200 with the existing health JSON; container user is not root.

**Step 5: Commit**

```bash
git add .dockerignore apps/cloud-control/Dockerfile infra/two-host/test.sh
git commit -m "build: package cloud-control for K3s"
```

### Task 4: Render pinned control and game manifests

**Files:**
- Create: `infra/two-host/render.sh`
- Create: `infra/two-host/templates/control.yaml.template`
- Create: `infra/two-host/templates/game-storage.yaml.template`
- Modify: `infra/two-host/test.sh`

**Step 1: Add failing render tests**

Render with documentation-only values and assert:

- PostgreSQL and `cloud-control` select and tolerate only the control node;
- Paper selects only the game node;
- PostgreSQL has only a `ClusterIP` service;
- both service accounts disable token automount and have no RBAC binding;
- images, ports, resource limits, storage capacities and local paths equal the
  configuration;
- the rendered files contain neither database password nor machine token;
- the Paper image/profile values still match the accepted catalog manifest.

**Step 2: Run tests and confirm failure**

Run: `bash infra/two-host/test.sh`

Expected: FAIL because rendering is absent.

**Step 3: Implement deterministic rendering**

Render to a caller-supplied empty directory. Create static local PVs with
`Retain`, matching PVCs and node affinity. Render PostgreSQL, its internal
service, `cloud-control`, and the accepted Paper resources. Secrets remain
references and are created separately by the deployer.

**Step 4: Validate output**

Run:

```bash
bash infra/two-host/test.sh
bash -n infra/two-host/render.sh
```

On K3s, also run server-side dry-run for every rendered file.

Expected: local tests PASS and Kubernetes accepts all resources.

**Step 5: Commit**

```bash
git add infra/two-host
git commit -m "feat: render the pinned two-host workloads"
```

### Task 5: Add safe reset, preparation, deployment and verification commands

**Files:**
- Create: `infra/two-host/reset-host.sh`
- Create: `infra/two-host/prepare-host.sh`
- Create: `infra/two-host/deploy.sh`
- Create: `infra/two-host/verify.sh`
- Modify: `infra/two-host/test.sh`

**Step 1: Add failing command-contract tests**

Assert that:

- reset requires an explicit `control` or `game` role and a validated config;
- reset refuses a control cluster with unrelated non-system workloads;
- only K3s state and validated `/var/lib/cloud/...` paths are deletion targets;
- preparation creates the configured data directory with the intended owner;
- deployment creates Secrets without printing them, builds/imports the control
  image, applies resources in dependency order and waits for rollouts;
- verification checks nodes, placement, resource values, private PostgreSQL,
  API-token presence, readiness, direct game TCP and available host reserve.

**Step 2: Run tests and confirm failure**

Run: `bash infra/two-host/test.sh`

Expected: FAIL because the commands do not exist.

**Step 3: Implement the commands**

Use strict shell mode, absolute paths, explicit role checks, temporary
directories from `mktemp -d`, cleanup traps and quoted variables. The ordinary
deploy path must never delete a PV/PVC or data directory. The destructive reset
must enumerate non-system workloads before invoking the official K3s uninstall
script and clearing only the two validated TES-151 data paths.

**Step 4: Run local validation**

Run:

```bash
bash infra/two-host/test.sh
bash -n infra/two-host/*.sh infra/k3s/*.sh
git diff --check
```

Expected: PASS.

**Step 5: Commit**

```bash
git add infra/two-host
git commit -m "feat: automate the TES-151 installation gate"
```

### Task 6: Document the operator boundary

**Files:**
- Create: `infra/two-host/README.md`
- Modify: `infra/README.md`
- Modify: `README.md`

**Step 1: Add a failing documentation/link check**

Extend the shell test to require documentation for compatible hosts, clean
checkout, configuration, credentials, explicit EULA, reset, first install,
reapply, readiness, direct ports, data paths, resource/storage distinction,
host reserve and troubleshooting. Check all new relative links exist.

**Step 2: Run the test and confirm failure**

Run: `bash infra/two-host/test.sh`

Expected: FAIL because the runbook is absent.

**Step 3: Write the scoped deployment runbook**

Document only the installation boundary owned by TES-151. State clearly that
token enforcement, lifecycle operations and the playable agent journey remain
F2/F3/F4, and that TES-152 will provide the contributor-oriented quickstart.

**Step 4: Run documentation checks**

Run: `bash infra/two-host/test.sh && git diff --check`

Expected: PASS.

**Step 5: Commit**

```bash
git add README.md infra/README.md infra/two-host
git commit -m "docs: add the TES-151 deployment runbook"
```

### Task 7: Rebuild the dedicated hosts and prove repeatability

**Files:**
- Create locally but do not commit: `infra/.local/tes-151/`
- Create after sanitization: `infra/evidence/tes-151-two-host-installation.md`

**Step 1: Capture a private pre-reset inventory**

Record K3s version, node roles, non-system workloads and the exact deletion
targets under `infra/.local/tes-151/`. Confirm Paper is the only non-system
workload before continuing.

**Step 2: Produce clean checkouts of the implementation commit**

Create a Git bundle from the task branch, transfer it using the configured SSH
identities and clone it into a new directory on each host. Confirm `git status
--short` is empty and record `git rev-parse HEAD` privately.

**Step 3: Run the destructive reset**

Run `reset-host.sh game ...` and then `reset-host.sh control ...`. Confirm K3s
units and selected data paths are absent. Do not alter provider firewall rules
or unrelated directories.

**Step 4: Install K3s and prepare storage**

Run the pinned control installer, retrieve the join token out-of-band, run the
pinned game installer, apply both firewall scripts and run `prepare-host.sh` on
each host.

**Step 5: Deploy and verify the first pass**

Run `deploy.sh` on `control-1`, followed by both K3s and TES-151 verifiers.
Record sanitized compatibility, versions, placement, resources, storage, host
reserve, health and direct TCP results.

**Step 6: Create durable probes**

Insert a uniquely named row in PostgreSQL and a marker file in the Paper volume
while Paper is stopped safely. Record only probe identifiers and hashes, never
credentials or host addresses.

**Step 7: Repeat the ordinary setup**

Run both pinned installers, preparation and deployment again without reset.
Verify that both probes, PV/PVC identities and readiness survive.

**Step 8: Sanitize and commit the evidence summary**

Write the exact commit, role-level host properties, versions, commands, logical
paths, resource figures, results and redaction statement. Exclude IPs, SSH
targets, node hostnames, credentials, raw firewall output and private paths.

```bash
git add infra/evidence/tes-151-two-host-installation.md
git commit -m "test: record TES-151 two-host deployment evidence"
```

### Task 8: Final verification and handoff

**Files:**
- Modify only if checks expose a defect: files from Tasks 1-7

**Step 1: Run all repository checks**

```bash
npm run check
bash infra/two-host/test.sh
bash -n infra/k3s/*.sh infra/two-host/*.sh
python3 benchmarks/minecraft/summarize.py --self-test
git diff --check origin/main...HEAD
git diff --exit-code origin/main...HEAD -- benchmarks/minecraft/package.json benchmarks/minecraft/package-lock.json
```

Expected: all commands exit 0; TypeScript reports 2 passing tests; benchmark
self-test reports `Metric parsing checks passed`.

**Step 2: Inspect the final repository state**

Run:

```bash
git status --short
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

Expected: clean worktree, focused TES-151 commits, no secrets or unrelated
changes.

**Step 3: Record exact evidence in Linear**

Comment on TES-151 with the commit series, every verification command and
result, the two-pass host outcome, evidence path and known limits.

**Step 4: Push and open the pull request**

Push the task branch, open a PR titled with `TES-151`, link the Linear issue and
include exact checks/results. Confirm it is conflict-free and mergeable, then
move TES-151 to `In Review` and request review.

**Step 5: Stop before merge**

Do not merge without the owner's explicit authorization. TES-151 becomes
`Done` only after merge. TES-152 stays separate and TES-146 remains `In
Progress` until all child acceptance gates are complete.
