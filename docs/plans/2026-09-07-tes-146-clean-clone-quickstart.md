# TES-146 Clean-Clone Quickstart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the existing TES-151 two-host operator runbook into a canonical, clean-clone contributor quickstart and record safe, reproducible evidence for TES-146/TES-152.

**Architecture:** Keep the existing `infra/two-host/*.sh` scripts and their configuration contract as the only installation mechanism. Improve the canonical README and repository entry points, then protect the documented contract with static checks and an evidence record that excludes operational secrets and host identifiers.

**Tech Stack:** Markdown, Bash static checks, npm workspaces/TypeScript, Python benchmark self-test, Git.

---

### Task 1: Make the two-host README a contributor-facing quickstart

**Files:**
- Modify: `infra/two-host/README.md`
- Reference: `infra/two-host/config.example.env`
- Reference: `infra/two-host/prepare-host.sh`
- Reference: `infra/two-host/deploy.sh`
- Reference: `infra/two-host/verify.sh`

**Step 1: Add the contributor-facing scope and prerequisites**

Rewrite the opening to identify TES-146/TES-152 and state the complete installation boundary. Keep the Ubuntu 24.04/systemd target, architectures, minimum CPU/RAM/disk, required host commands, workload placement and the worker/host reserve distinction.

**Step 2: Document clean-clone and configuration setup**

Describe cloning the same verified commit on both hosts, checking a clean worktree, copying the example config into ignored `infra/.local/`, replacing documentation values, generating operator-owned secrets, applying `0600`, and keeping secret fields off `game-1`. Keep the explicit EULA acceptance and the three address roles.

**Step 3: Document ordered installation commands**

Provide copyable sections for control host preparation, pinned K3s server installation, firewall setup, protected join-token transfer, game host agent installation, game firewall, host preparation, control deployment and verification. State which commands run on which host and what the verifier proves.

**Step 4: Document the non-destructive repeatability gate**

Explain how to record private PostgreSQL/world probes, rerun preparation/install/firewall/deploy/verify without `reset-host.sh`, and confirm PVC identity, probe rows, marker hashes and Ready workloads remain intact. Link the TES-151 evidence as the existing live installation result.

**Step 5: Document limits and troubleshooting**

Separate installation readiness from F2/F3 control operations and TES-148 acceptance. Explain direct game TCP access, private PostgreSQL/K3s administration, storage budget versus filesystem quota, and the existing troubleshooting cases. Do not add new runtime behavior or claim public/Cloudflare support.

**Step 6: Review the README for secret leakage and broken relative links**

Run `rg -n 'password|token|192\.0\.2|198\.51\.100|10\.0\.0' infra/two-host/README.md` and inspect every relative link target. Documentation values are allowed only when clearly identified as examples; no private operational values may be added.

**Step 7: Commit the quickstart**

Run:

```bash
git add infra/two-host/README.md
git commit -m "docs: turn TES-151 runbook into TES-146 quickstart"
```

Expected: one focused documentation commit.

### Task 2: Make repository entry points and evidence point to the gate

**Files:**
- Modify: `README.md`
- Modify: `infra/README.md`
- Create: `infra/evidence/tes-152-clean-clone-quickstart.md`

**Step 1: Add canonical quickstart links**

Link the repository overview and infrastructure overview directly to `infra/two-host/README.md`, identifying it as the clean-clone two-host installation guide and preserving the later F2/F3 boundary.

**Step 2: Record safe reproducibility evidence**

Create the evidence record with the verified source commit, local verification commands, passing results, host requirements and the evidence boundary. Reference TES-151’s live two-host installation evidence without copying addresses, credentials, provider identifiers or raw logs.

**Step 3: Validate the evidence record**

Check that the record contains versions, commands, requirements, reapply/persistence references and no secrets or private host details. Confirm all links resolve from the repository.

**Step 4: Commit entry points and evidence**

Run:

```bash
git add README.md infra/README.md infra/evidence/tes-152-clean-clone-quickstart.md
git commit -m "docs: record TES-152 clean-clone quickstart evidence"
```

Expected: one focused documentation/evidence commit.

### Task 3: Add static documentation gates to the two-host test

**Files:**
- Modify: `infra/two-host/test.sh`

**Step 1: Add a helper for documentation assertions**

Reuse the existing `expect_file_contains` and `expect_file_excludes` helpers. Define explicit variables for the canonical README, repository evidence and top-level entry points if needed.

**Step 2: Add acceptance-oriented README assertions**

Assert that the canonical quickstart names Ubuntu 24.04, clean clone/commit, operator-owned credentials, explicit EULA, both hosts, pinned K3s, `prepare-host.sh`, `deploy.sh`, `verify.sh`, second-pass/reapply preservation, the 2 GiB heap, 3 GiB container memory, 10 GiB storage budget, host reserve, direct TCP path, all three address variables, troubleshooting and F2/F3 boundaries.

**Step 3: Add link and evidence assertions**

Assert that the evidence file exists and contains the verification commands and secret/evidence boundary. Assert that the top-level README and `infra/README.md` reference the canonical quickstart. Keep the checks static so they work on a clean clone without live hosts.

**Step 4: Run the focused test and fix only documentation-gate failures**

Run:

```bash
bash infra/two-host/test.sh
```

Expected: `two-host tests passed`.

**Step 5: Commit the static gates**

Run:

```bash
git add infra/two-host/test.sh
git commit -m "test: guard TES-152 quickstart contract"
```

Expected: one focused test commit.

### Task 4: Run the complete verification and prepare Linear evidence

**Files:**
- Inspect: all changed files and final Git diff

**Step 1: Run shell syntax and focused checks**

```bash
bash infra/two-host/test.sh
for script in infra/k3s/*.sh infra/two-host/*.sh; do bash -n "$script"; done
```

Expected: the test prints `two-host tests passed`; every shell script exits successfully.

**Step 2: Run the root TypeScript check**

```bash
npm run check
```

Expected: build succeeds and both compiled `cloud-control` tests pass. If the sandbox denies localhost listeners, rerun this command with the approved elevated test environment and record the successful result.

**Step 3: Run the Minecraft benchmark self-test**

```bash
python3 benchmarks/minecraft/summarize.py --self-test
```

Expected: `Metric parsing checks passed`; `benchmarks/minecraft/package.json` and its lockfile remain unchanged.

**Step 4: Inspect final diff and worktree**

```bash
git diff --check
git diff origin/main...HEAD --stat
git status --short --branch
```

Expected: no whitespace errors, only TES-146/TES-152 files plus the committed design/plan, and a clean worktree.

**Step 5: Record exact evidence in Linear**

Add a TES-146 comment with the implementation commit SHAs, verification commands/results, evidence file path and any live-installation boundary. Update TES-152 with its commit/evidence and move it to `In Review` only if its pull request is open, conflict-free and ready; do not mark either issue `Done` before merge.

**Step 6: Open the focused pull request**

Use the TES-146 branch and include the Linear identifier, summary, acceptance mapping, verification results, and the fact that credentials and host-specific operational evidence remain outside Git. Request review; do not merge, force-push or delete branches.
