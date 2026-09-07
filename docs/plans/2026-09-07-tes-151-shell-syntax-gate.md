# TES-151 Shell Syntax Gate Correction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the control installer parse error and ensure the TES-151 test suite validates every shell script individually.

**Architecture:** Extend the existing shell test with a per-file Bash syntax loop, prove that it catches the current defect, then make the smallest diagnostic-text correction. Regenerate the deployment bundle and remote clean checkouts so host evidence is tied to the corrected commit.

**Tech Stack:** Bash, Git, K3s deployment scripts.

---

### Task 1: Add the syntax regression gate

**Files:**
- Modify: `infra/two-host/test.sh`

**Step 1: Write the failing test**

Add a loop over `infra/k3s/*.sh` and `infra/two-host/*.sh` that runs
`bash -n "$script"` for each path.

**Step 2: Run the test to verify it fails**

Run: `bash infra/two-host/test.sh`

Expected: FAIL with the unmatched-quote parse error from
`infra/k3s/install-control.sh`.

### Task 2: Correct the parser defect

**Files:**
- Modify: `infra/k3s/install-control.sh:13`

**Step 1: Write the minimal correction**

Replace `control-1's private IPv4 address` with
`the private IPv4 address for control-1`.

**Step 2: Run focused verification**

Run:

```bash
bash infra/two-host/test.sh
for script in infra/k3s/*.sh infra/two-host/*.sh; do bash -n "$script"; done
git diff --check
```

Expected: all commands pass and the test prints `two-host tests passed`.

**Step 3: Commit**

```bash
git add infra/k3s/install-control.sh infra/two-host/test.sh
git commit -m "test: validate every TES-151 shell script"
```

### Task 3: Refresh deployment inputs

**Files:**
- Replace locally: `infra/.local/tes-151/tes-151.bundle`

**Step 1: Recreate the bundle**

Create a bundle at the new HEAD and verify it with `git bundle verify`.

**Step 2: Create new remote checkouts**

Transfer the bundle to both hosts, clone it into new temporary directories,
copy the role-specific ignored configuration, and verify an empty
`git status --short` at the exact new HEAD.

**Step 3: Resume the TES-151 plan**

Run Tasks 7 and 8 of
`docs/plans/2026-09-06-tes-151-two-host-deployment.md` from the corrected
checkouts. Do not repeat the destructive reset because both hosts are already
verified empty after the first attempt.

### Task 4: Separate the game node and NAT addresses

**Files:**
- Modify: `infra/two-host/config.example.env`
- Modify: `infra/two-host/lib.sh`
- Modify: `infra/two-host/test.sh`
- Modify: `infra/k3s/install-game.sh`
- Modify: `infra/k3s/README.md`
- Modify: `infra/two-host/README.md`
- Modify: `infra/two-host/verify.sh`

**Step 1: Extend the failing configuration and source tests**

Add required `GAME_NODE_ADDRESS` and `GAME_CLUSTER_SOURCE_ADDRESS` values,
invalid-address cases, and assertions that the game installer uses only
`GAME_NODE_ADDRESS` for `--node-ip`. Require the verifier and runbook to cover
all three game address roles.

**Step 2: Run the test to verify it fails**

Run: `bash infra/two-host/test.sh`

Expected: FAIL because the new address contract is not implemented.

**Step 3: Implement the minimal NAT-aware contract**

Validate both new IPv4 values, use `GAME_NODE_ADDRESS` in the K3s installer,
use `GAME_CLUSTER_SOURCE_ADDRESS` in the control firewall command, and retain
`GAME_DIRECT_ADDRESS` for the player-facing TCP check. Verify the Kubernetes
node InternalIP equals `GAME_NODE_ADDRESS`.

**Step 4: Run focused verification**

Run:

```bash
bash infra/two-host/test.sh
for script in infra/k3s/*.sh infra/two-host/*.sh; do bash -n "$script"; done
git diff --check
```

Expected: all commands pass.

**Step 5: Commit and refresh deployment inputs**

Commit the focused source/docs change, update the ignored role configurations
with the detected local game interface address, rebuild and verify the bundle,
then create fresh remote checkouts at the new HEAD. Reset only the partial game
agent installation before resuming deployment; keep the healthy control server.
