import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";

import { createRequestHandler, handleRequest } from "../src/app.js";
import { ControlError, type Mutation, type ServerRecord } from "../src/lifecycle.js";

const SERVER_ID = "44752f9d-5564-4e43-9346-cd30a99a1613";

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

async function withAuthenticatedServer(
  control: Parameters<typeof createRequestHandler>[0],
  run: (origin: string) => Promise<void>
): Promise<void> {
  const server = createServer(createRequestHandler(control));
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

test("machine identity requires a valid bearer token", async () => {
  const control = createControl().control;
  await withAuthenticatedServer(control, async (origin) => {
    const missing = await fetch(`${origin}/v1/whoami`);
    assert.equal(missing.status, 401);

    const invalid = await fetch(`${origin}/v1/whoami`, {
      headers: { authorization: "Bearer wrong" }
    });
    assert.equal(invalid.status, 401);

    const valid = await fetch(`${origin}/v1/whoami`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    assert.equal(valid.status, 200);
    assert.deepEqual(await valid.json(), { id: "principal-1", subject: "operator" });
  });
});

function createControl() {
  let server: ServerRecord = {
    id: SERVER_ID,
    principal_id: "principal-1",
    logical_name: "one",
    recipe_id: "paper-26.2-121",
    profile_id: "two-player",
    world_identity: `cloud-world-${SERVER_ID}`,
    desired_state: "running",
    state: "queued",
    generation: 1,
    observed_generation: 0,
    last_request_id: "create-one",
    endpoint: null
  };
  const mutations: Mutation[] = [];
  return {
    control: {
      authenticate: async (token: string) => token === "operator-machine-token"
        ? { id: "principal-1", subject: "operator" }
        : null,
      mutate: async (principalId: string, requestId: string, mutation: Mutation) => {
        assert.equal(principalId, "principal-1");
        mutations.push(mutation);
        return { request_id: requestId, server_id: SERVER_ID, state: "queued" as const,
          status_url: `/v1/servers/${SERVER_ID}` };
      },
      getServer: async (principalId: string, serverId: string) => {
        if (principalId !== "principal-1" || serverId !== SERVER_ID) {
          throw new ControlError("server_not_found", 404);
        }
        return server;
      }
    },
    mutations,
    setRunning() {
      server = { ...server, state: "running", observed_generation: 1,
        endpoint: { host: "game.invalid", port: 30_001 } };
    }
  };
}

test("REST create is asynchronous and status exposes only a ready endpoint", async () => {
  const fake = createControl();
  await withAuthenticatedServer(fake.control, async (origin) => {
    const created = await fetch(`${origin}/v1/servers`, {
      method: "POST",
      headers: {
        authorization: "Bearer operator-machine-token",
        "content-type": "application/json"
      },
      body: JSON.stringify({ client_request_id: "create-one", name: "one", eula_accepted: true })
    });
    assert.equal(created.status, 202);
    assert.deepEqual(await created.json(), {
      request_id: "create-one",
      server_id: SERVER_ID,
      state: "queued",
      status_url: `/v1/servers/${SERVER_ID}`
    });
    assert.deepEqual(fake.mutations, [{ operation: "create", name: "one", eula_accepted: true }]);

    const first = await fetch(`${origin}/v1/servers/${SERVER_ID}`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    const second = await fetch(`${origin}/v1/servers/${SERVER_ID}`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    assert.equal(first.status, 200);
    assert.deepEqual(await first.json(), await second.json());
  });
});

test("REST status gates endpoint readiness and ownership", async () => {
  const fake = createControl();
  await withAuthenticatedServer(fake.control, async (origin) => {
    const queued = await fetch(`${origin}/v1/servers/${SERVER_ID}`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    assert.deepEqual(await queued.json(), {
      server_id: SERVER_ID,
      name: "one",
      state: "queued",
      allocation_path: "cold",
      status_url: `/v1/servers/${SERVER_ID}`
    });

    fake.setRunning();
    const running = await fetch(`${origin}/v1/servers/${SERVER_ID}`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    assert.deepEqual(await running.json(), {
      server_id: SERVER_ID,
      name: "one",
      state: "running",
      allocation_path: "cold",
      status_url: `/v1/servers/${SERVER_ID}`,
      endpoint: { host: "game.invalid", port: 30_001 }
    });

    const missing = await fetch(`${origin}/v1/servers/22e65178-a174-4ef3-8434-18765925c08f`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    assert.equal(missing.status, 404);
    assert.deepEqual(await missing.json(), { error: "server_not_found" });
  });
});

test("REST create validates authentication, JSON size, fields and EULA", async () => {
  const fake = createControl();
  await withAuthenticatedServer(fake.control, async (origin) => {
    const cases: Array<[RequestInit, number, object]> = [
      [{ method: "POST", headers: { "content-type": "application/json" }, body: "{}" },
        401, { error: "unauthorized" }],
      [{ method: "POST", headers: { authorization: "Bearer operator-machine-token" }, body: "{}" },
        415, { error: "unsupported_media_type" }],
      [{ method: "POST", headers: { authorization: "Bearer operator-machine-token",
        "content-type": "application/json" }, body: "{" }, 400, { error: "invalid_json" }],
      [{ method: "POST", headers: { authorization: "Bearer operator-machine-token",
        "content-type": "application/json" }, body: JSON.stringify({ client_request_id: "create-one",
          name: "one", eula_accepted: false }) }, 409,
        { error: "action_required", action_required: "accept_eula" }],
      [{ method: "POST", headers: { authorization: "Bearer operator-machine-token",
        "content-type": "application/json" }, body: JSON.stringify({ client_request_id: "create-one",
          name: "one" }) }, 409, { error: "action_required", action_required: "accept_eula" }],
      [{ method: "POST", headers: { authorization: "Bearer operator-machine-token",
        "content-type": "application/json" }, body: JSON.stringify({ client_request_id: 1,
          name: "one", eula_accepted: true }) }, 400, { error: "invalid_request" }],
      [{ method: "POST", headers: { authorization: "Bearer operator-machine-token",
        "content-type": "application/json" }, body: JSON.stringify({ client_request_id: "create-large",
          name: "x".repeat(17_000), eula_accepted: true }) }, 413, { error: "request_too_large" }]
    ];
    for (const [request, status, body] of cases) {
      const response = await fetch(`${origin}/v1/servers`, request);
      assert.equal(response.status, status);
      assert.deepEqual(await response.json(), body);
    }
    const invalidId = await fetch(`${origin}/v1/servers/not-a-uuid`, {
      headers: { authorization: "Bearer operator-machine-token" }
    });
    assert.equal(invalidId.status, 400);
    assert.deepEqual(await invalidId.json(), { error: "invalid_server_id" });
    assert.equal(fake.mutations.length, 0);
  });
});
