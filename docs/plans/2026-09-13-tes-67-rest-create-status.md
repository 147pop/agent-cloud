# TES-67 REST Create and Status Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose authenticated, asynchronous REST create and status operations through `cloud-control` while preserving the existing durable lifecycle contract.

**Architecture:** Route both operations through the existing `ControlStore`; no parallel lifecycle service or dependency is added. The HTTP boundary validates authentication, content type, bounded JSON, EULA acceptance, and server IDs, while `ControlStore` remains responsible for ownership, idempotency, durable state, and event evidence.

**Tech Stack:** Node.js 22 HTTP server, TypeScript, PostgreSQL through `pg`, built-in `node:test` and `node:assert`.

---

### Task 1: Make EULA acceptance part of durable creation

**Files:**
- Modify: `apps/cloud-control/src/lifecycle.ts`
- Modify: `apps/cloud-control/src/database.ts`
- Modify: `apps/cloud-control/test/lifecycle.integration.ts`

**Step 1: Write the failing integration assertion**

Update create mutations to carry the literal `eula_accepted: true`, then assert that the creation event records it:

```ts
const accepted = await store.mutate(owner.id, "create-one", {
  operation: "create",
  name: "one",
  eula_accepted: true
});
const creation = await inspection.query<{ payload: { eula_accepted?: boolean } }>(
  "SELECT payload FROM events WHERE server_id = $1 AND event_type = 'intent_recorded' ORDER BY id LIMIT 1",
  [accepted.server_id]
);
assert.equal(creation.rows[0]?.payload.eula_accepted, true);
```

**Step 2: Run the build to verify it fails**

Run: `npm run build`

Expected: TypeScript rejects `eula_accepted` because the create mutation does not yet define it.

**Step 3: Implement the minimum durable change**

Require explicit acceptance on create mutations:

```ts
export type Mutation = {
  operation: "create";
  name: string;
  eula_accepted: true;
} | {
  operation: "start" | "stop";
  server_id: string;
};
```

Include `eula_accepted` in the create request digest and in the existing
`intent_recorded` event payload. Update all existing internal create calls to
pass the literal `true`; do not add a new table or column.

**Step 4: Run focused checks**

Run: `npm run check`

Expected: build succeeds and all compiled unit tests pass.

If `TEST_DATABASE_URL` is available, run:
`npm run test:integration`

Expected: all PostgreSQL integration tests pass, including the EULA event assertion.

**Step 5: Commit**

```bash
git add apps/cloud-control/src/lifecycle.ts apps/cloud-control/src/database.ts apps/cloud-control/test
git commit -m "feat: record TES-67 EULA acceptance"
```

### Task 2: Add authenticated create and status routes

**Files:**
- Modify: `apps/cloud-control/src/app.ts`
- Modify: `apps/cloud-control/test/app.test.ts`

**Step 1: Write failing HTTP tests**

Add one focused test with a small structural fake for the existing store methods.
Cover:

```ts
await fetch(`${origin}/v1/servers`, {
  method: "POST",
  headers: {
    authorization: "Bearer operator-machine-token",
    "content-type": "application/json"
  },
  body: JSON.stringify({
    client_request_id: "create-one",
    name: "one",
    eula_accepted: true
  })
});
```

Assert `202`, the durable `request_id`, `server_id`, typed queued state and
status URL. Also assert:

- missing/false EULA returns `409` and `action_required: "accept_eula"`;
- malformed JSON and fields return `400`;
- non-JSON input returns `415`;
- bodies over 16 KiB return `413`;
- missing/invalid bearer tokens return `401`;
- repeated owner status reads are identical;
- another owner's server returns the existing actionable `404`;
- `endpoint` is absent until `running` and present when `running`.

**Step 2: Run the focused test to verify it fails**

Run: `npm run build && node --test apps/cloud-control/dist/test/app.test.js`

Expected: the new requests return `404` because the routes do not exist.

**Step 3: Implement the smallest HTTP boundary**

Use `Pick<ControlStore, "authenticate" | "mutate" | "getServer">` as the
handler dependency. Add:

```ts
const MAX_JSON_BYTES = 16 * 1024;

// POST /v1/servers -> control.mutate(principal.id, client_request_id, {
//   operation: "create", name, eula_accepted: true
// })

// GET /v1/servers/:uuid -> control.getServer(principal.id, serverId)
```

Use native request streaming and `JSON.parse`; do not add a web framework. Map
known `ControlError` values to their existing status and `{ error: code }`.
Return `500 { error: "internal_error" }` for unknown exceptions without leaking
details. The status response includes `allocation_path: "cold"` and includes
`endpoint` only when state is `running` and an endpoint exists.

**Step 4: Run focused and full checks**

Run: `npm run build && node --test apps/cloud-control/dist/test/app.test.js`

Expected: all HTTP tests pass.

Run: `npm run check`

Expected: all compiled unit tests pass.

**Step 5: Commit**

```bash
git add apps/cloud-control/src/app.ts apps/cloud-control/test/app.test.ts
git commit -m "feat: expose TES-67 REST create and status"
```

### Task 3: Document and verify the delivered contract

**Files:**
- Modify: `apps/cloud-control/README.md`
- Create: `infra/evidence/tes-67-rest-create-status.md`

**Step 1: Document the two operations**

Add concise `curl` examples using placeholder values only. State that create is
asynchronous, EULA acceptance is mandatory, status is owner-scoped, the current
allocation path is cold, and an endpoint is returned only after protocol
readiness.

**Step 2: Record reproducible evidence**

Record the branch commit, commands, exact test counts, and whether PostgreSQL
integration was run. Do not include credentials, host addresses, or operator
identifiers.

**Step 3: Run repository verification**

Run: `npm run check`

Expected: build succeeds and all compiled unit tests pass.

Run: `git diff --check`

Expected: no output.

Run: `git status --short`

Expected: only the intended documentation and evidence files before commit.

**Step 4: Commit**

```bash
git add apps/cloud-control/README.md infra/evidence/tes-67-rest-create-status.md
git commit -m "docs: record TES-67 REST verification"
```

### Task 4: Handoff

**Files:**
- No repository changes expected

**Step 1: Inspect the final branch**

Run: `git diff --stat origin/main...HEAD`

Expected: only TES-67 design, implementation, tests, README, and evidence.

Run: `git status --short --branch`

Expected: clean TES-67 branch.

**Step 2: Publish and open review**

Push the TES-67 branch and open a pull request titled with `TES-67`. Include the
Linear link and exact verification commands/results. Do not merge without user
authorization.

**Step 3: Update Linear**

Comment on TES-67 with implementation commits, pull request, and exact
verification results. Move TES-67 to `In Review` only when the pull request is
open, conflict-free, and ready; keep TES-147 in `In Progress`.
