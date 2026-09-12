import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";

import { createRequestHandler, handleRequest, type Authenticator } from "../src/app.js";

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
  authenticator: Authenticator,
  run: (origin: string) => Promise<void>
): Promise<void> {
  const server = createServer(createRequestHandler(authenticator));
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
  const authenticator: Authenticator = {
    authenticate: async (token) => token === "operator-machine-token"
      ? { id: "principal-1", subject: "operator" }
      : null
  };
  await withAuthenticatedServer(authenticator, async (origin) => {
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
