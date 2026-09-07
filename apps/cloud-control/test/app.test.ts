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
