# TES-150 Root TypeScript Workspace Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the repository into an npm workspace with a minimal, runnable and tested TypeScript `cloud-control` application while preserving the existing benchmark tooling as an independent component.

**Architecture:** The repository root owns npm workspace orchestration and shared TypeScript defaults. `apps/cloud-control` is an ESM Node application with one dependency-free HTTP health endpoint; it does not include PostgreSQL, Docker, Minecraft, REST product operations, MCP or web UI yet. Tests use Node's built-in test runner so this scaffold adds only TypeScript and Node type definitions.

**Tech Stack:** Node.js `>=22`, npm workspaces, TypeScript `7.0.2`, `@types/node` `22.20.1`, ESM, `node:http`, `node:test`.

---

## Scope boundaries

TES-150 includes:

- Root npm workspace and lockfile.
- Shared strict TypeScript configuration.
- Minimal `@cloud/cloud-control` application.
- `GET /healthz` and deterministic `404` behavior.
- Root build and test commands.
- Ignore rules for Node build artifacts.

TES-150 excludes:

- Dockerfiles, Compose and Docker Engine access; those belong to TES-151.
- PostgreSQL, migrations and the local development principal; those belong to TES-66.
- Runtime contracts and reconciliation; those belong to TES-158.
- Minecraft lifecycle behavior; that belongs to TES-153 and TES-154.
- Product REST operations, MCP and web pages; those belong to TES-67, TES-68, TES-74 and TES-76.
- CI workflow creation and public quickstart documentation.

## Required resulting tree

```text
.
├── package.json
├── package-lock.json
├── tsconfig.base.json
└── apps
    └── cloud-control
        ├── package.json
        ├── tsconfig.json
        ├── src
        │   ├── app.ts
        │   └── index.ts
        └── test
            └── app.test.ts
```

### Task 1: Add root workspace metadata

**Files:**

- Create: `package.json`
- Modify: `.gitignore`

**Step 1: Add the root package manifest**

Create `package.json`:

```json
{
  "name": "cloud",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=22"
  },
  "workspaces": [
    "apps/*",
    "packages/*"
  ],
  "scripts": {
    "build": "npm run build --workspace @cloud/cloud-control",
    "test": "npm run test --workspace @cloud/cloud-control",
    "check": "npm run build && npm run test:compiled --workspace @cloud/cloud-control"
  },
  "devDependencies": {
    "@types/node": "22.20.1",
    "typescript": "7.0.2"
  }
}
```

Do not add `benchmarks/minecraft` to the root workspaces. Its custom Mineflayer dependency graph and lockfile remain independent.

**Step 2: Ignore generated Node artifacts**

Append to `.gitignore`:

```gitignore
node_modules/
dist/
*.tsbuildinfo
```

**Step 3: Verify the manifest before installation**

Run:

```bash
npm pkg get name private engines workspaces scripts
```

Expected: valid JSON showing `cloud`, `private: true`, Node `>=22`, both workspace patterns and the three root scripts.

**Step 4: Commit the workspace metadata**

```bash
git add package.json .gitignore
git commit -m "build: add root npm workspace"
```

### Task 2: Add strict shared TypeScript configuration

**Files:**

- Create: `tsconfig.base.json`

**Step 1: Create the shared compiler configuration**

Create `tsconfig.base.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"],
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "forceConsistentCasingInFileNames": true,
    "verbatimModuleSyntax": true,
    "declaration": true,
    "sourceMap": true,
    "types": ["node"]
  }
}
```

**Step 2: Verify JSON parsing**

Run:

```bash
node -e "JSON.parse(require('node:fs').readFileSync('tsconfig.base.json', 'utf8'))"
```

Expected: exit code `0`, no output.

**Step 3: Commit the compiler configuration**

```bash
git add tsconfig.base.json
git commit -m "build: add strict TypeScript defaults"
```

### Task 3: Define the cloud-control workspace

**Files:**

- Create: `apps/cloud-control/package.json`
- Create: `apps/cloud-control/tsconfig.json`

**Step 1: Create the application package manifest**

Create `apps/cloud-control/package.json`:

```json
{
  "name": "@cloud/cloud-control",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=22"
  },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/src/index.js",
    "test": "npm run build && npm run test:compiled",
    "test:compiled": "node --test dist/test/app.test.js"
  }
}
```

**Step 2: Create the application compiler configuration**

Create `apps/cloud-control/tsconfig.json`:

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "rootDir": ".",
    "outDir": "dist"
  },
  "include": ["src/**/*.ts", "test/**/*.ts"]
}
```

**Step 3: Verify npm discovers exactly the intended workspace**

Run:

```bash
npm pkg get name --workspaces
```

Expected:

```json
{
  "@cloud/cloud-control": "@cloud/cloud-control"
}
```

The command may warn that dependencies have not been installed yet; it must not treat `benchmarks/minecraft` as a workspace.

**Step 4: Commit the application metadata**

```bash
git add apps/cloud-control/package.json apps/cloud-control/tsconfig.json
git commit -m "build: define cloud-control workspace"
```

### Task 4: Test-drive the HTTP application boundary

**Files:**

- Create: `apps/cloud-control/test/app.test.ts`
- Create: `apps/cloud-control/src/app.ts`

**Step 1: Write the failing HTTP tests**

Create `apps/cloud-control/test/app.test.ts`:

```typescript
import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";

import { handleRequest } from "../src/app.js";

async function withServer(run: (origin: string) => Promise<void>): Promise<void> {
  const server = createServer(handleRequest);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");

  const address = server.address();
  assert(address !== null && typeof address !== "string");

  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    server.close();
    await once(server, "close");
  }
}

test("GET /healthz reports cloud-control health", async () => {
  await withServer(async (origin) => {
    const response = await fetch(`${origin}/healthz`);

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      service: "cloud-control",
      status: "ok"
    });
  });
});

test("unknown routes return a typed 404", async () => {
  await withServer(async (origin) => {
    const response = await fetch(`${origin}/missing`);

    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: "not_found" });
  });
});
```

**Step 2: Install the pinned toolchain and verify the test cannot build**

Run:

```bash
npm install
npm test
```

Expected: `npm install` creates `package-lock.json`; `npm test` fails because `apps/cloud-control/src/app.ts` does not exist.

**Step 3: Implement the minimal request handler**

Create `apps/cloud-control/src/app.ts`:

```typescript
import type { IncomingMessage, ServerResponse } from "node:http";

function sendJson(
  response: ServerResponse,
  statusCode: number,
  body: Record<string, string>
): void {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(body));
}

export function handleRequest(
  request: IncomingMessage,
  response: ServerResponse
): void {
  if (request.method === "GET" && request.url === "/healthz") {
    sendJson(response, 200, { service: "cloud-control", status: "ok" });
    return;
  }

  sendJson(response, 404, { error: "not_found" });
}
```

**Step 4: Run the focused tests**

Run:

```bash
npm test
```

Expected: two passing tests and exit code `0`.

**Step 5: Commit the tested application boundary and lockfile**

```bash
git add package-lock.json apps/cloud-control/src/app.ts apps/cloud-control/test/app.test.ts
git commit -m "feat: add cloud-control health boundary"
```

### Task 5: Add the runnable process entry point

**Files:**

- Create: `apps/cloud-control/src/index.ts`

**Step 1: Create the process entry point**

Create `apps/cloud-control/src/index.ts`:

```typescript
import { createServer } from "node:http";

import { handleRequest } from "./app.js";

const host = process.env.HOST ?? "127.0.0.1";
const port = Number(process.env.PORT ?? "3000");

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

const server = createServer(handleRequest);

server.listen(port, host, () => {
  process.stdout.write(
    `${JSON.stringify({ event: "listening", host, port, service: "cloud-control" })}\n`
  );
});
```

Graceful process shutdown, configuration loading and readiness dependencies are intentionally deferred. TES-150 only proves that the root application can build, test and run.

**Step 2: Build the workspace**

Run:

```bash
npm run build
```

Expected: exit code `0`; compiled files appear under `apps/cloud-control/dist`.

**Step 3: Smoke-test the process**

In terminal one:

```bash
HOST=127.0.0.1 PORT=3000 npm start --workspace @cloud/cloud-control
```

Expected: one JSON `listening` event naming `cloud-control`, host `127.0.0.1` and port `3000`.

In terminal two:

```bash
curl --fail --silent http://127.0.0.1:3000/healthz
```

Expected:

```json
{"service":"cloud-control","status":"ok"}
```

Stop terminal one with `Ctrl-C`.

**Step 4: Commit the process entry point**

```bash
git add apps/cloud-control/src/index.ts
git commit -m "feat: add cloud-control process entrypoint"
```

### Task 6: Verify TES-150 acceptance and prepare handoff

**Files:**

- Modify only if required by a failed check: files introduced by Tasks 1-5.

**Step 1: Run the complete root check**

```bash
npm run check
```

Expected: TypeScript build succeeds and two tests pass.

**Step 2: Re-run the pre-existing benchmark parser check**

```bash
python3 benchmarks/minecraft/summarize.py --self-test
```

Expected: `Metric parsing checks passed`.

**Step 3: Verify generated files are ignored and the benchmark package is untouched**

```bash
git status --short
git diff -- benchmarks/minecraft/package.json benchmarks/minecraft/package-lock.json
```

Expected: no `node_modules`, `dist` or `*.tsbuildinfo` entries; no diff for either benchmark package file.

**Step 4: Verify commit scope**

```bash
git log --oneline --decorate -6
git diff HEAD~5 --stat
```

Expected: five focused TES-150 implementation commits after the pre-existing handoff commit, containing only root workspace configuration and `apps/cloud-control`.

**Step 5: Update Linear after evidence exists**

- Add the final commit and the exact `npm run check` and benchmark self-test results to TES-150.
- Mark TES-150 Done only after all checks above pass.
- Leave TES-146 In Progress.
- Move TES-151 to In Progress as the next executable task.

Do not mark TES-150 complete merely because the files exist.
