import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";

import { createRequestHandler } from "../src/app.js";
import { runCli } from "../src/cli.js";
import { ControlError, type Mutation, type ServerRecord, type ServerState } from "../src/lifecycle.js";

const SERVER_ID = "44752f9d-5564-4e43-9346-cd30a99a1613";
const TOKEN = "operator-machine-token";

// Each status read advances the fake one step toward the desired state.
function createControl() {
  const mutations: Array<[string, Mutation]> = [];
  const replies = new Map<string, string>();
  let states: ServerState[] = ["queued"];
  let server: ServerRecord = {
    id: SERVER_ID, principal_id: "principal-1", logical_name: "one", recipe_id: "paper-26.2-121",
    profile_id: "two-player", world_identity: `cloud-world-${SERVER_ID}`, desired_state: "running",
    state: "queued", generation: 1, observed_generation: 0, last_request_id: "", endpoint: null
  };
  return {
    mutations,
    control: {
      authenticate: async (token: string) => token === TOKEN ? { id: "principal-1", subject: "operator" } : null,
      mutate: async (_principalId: string, requestId: string, mutation: Mutation) => {
        if (mutation.operation === "create" && mutations.some(([id, m]) => m.operation === "create" && id !== requestId)) {
          throw new ControlError("capacity_unavailable", 409);
        }
        if (mutation.operation !== "create" && mutation.server_id !== SERVER_ID) {
          throw new ControlError("server_not_found", 404);
        }
        const body = JSON.stringify(mutation);
        const previous = replies.get(requestId);
        if (previous !== undefined && previous !== body) throw new ControlError("idempotency_key_reused", 409);
        if (previous === undefined) {
          replies.set(requestId, body);
          mutations.push([requestId, mutation]);
          states = mutation.operation === "stop" ? ["stopping", "stopped"] : ["queued", "provisioning", "running"];
        }
        return { request_id: requestId, server_id: SERVER_ID, state: states[0]!, status_url: `/v1/servers/${SERVER_ID}` };
      },
      getServer: async (_principalId: string, serverId: string) => {
        if (serverId !== SERVER_ID) throw new ControlError("server_not_found", 404);
        const state = states.length > 1 ? states.shift()! : states[0]!;
        server = { ...server, state, endpoint: state === "running" ? { host: "127.0.0.1", port: 25565 } : null };
        return server;
      }
    }
  };
}

async function withCli(
  run: (cli: (...argv: string[]) => Promise<{ code: number; out: unknown[]; err: string[] }>,
    fake: ReturnType<typeof createControl>) => Promise<void>,
  env: Record<string, string | undefined> = { CLOUD_MACHINE_TOKEN: TOKEN }
): Promise<void> {
  const fake = createControl();
  const server = createServer(createRequestHandler(fake.control));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address !== null && typeof address !== "string");
  try {
    await run(async (...argv) => {
      const out: unknown[] = [];
      const err: string[] = [];
      const code = await runCli(argv, { env: { CLOUD_CONTROL_URL: `http://127.0.0.1:${address.port}`, ...env },
        stdout: line => out.push(JSON.parse(line)), stderr: line => err.push(line), pollMs: 1 });
      return { code, out, err };
    }, fake);
  } finally {
    server.close();
    await once(server, "close");
  }
}

test("CLI completes create, status, stop and start with the endpoint only once running", async () => {
  await withCli(async (cli, fake) => {
    const created = await cli("create", "one", "--accept-eula", "--request-id", "create-one", "--wait");
    assert.equal(created.code, 0);
    assert.deepEqual(created.out[0], { request_id: "create-one", server_id: SERVER_ID, state: "queued",
      status_url: `/v1/servers/${SERVER_ID}` });
    assert.deepEqual(created.out[1], { server_id: SERVER_ID, name: "one", state: "running",
      allocation_path: "cold", status_url: `/v1/servers/${SERVER_ID}`, endpoint: { host: "127.0.0.1", port: 25565 } });

    const stopped = await cli("stop", SERVER_ID, "--request-id", "stop-one", "--wait");
    assert.equal(stopped.code, 0);
    assert.equal((stopped.out[0] as { state: string }).state, "stopping");
    assert.deepEqual(stopped.out[1], { server_id: SERVER_ID, name: "one", state: "stopped",
      allocation_path: "cold", status_url: `/v1/servers/${SERVER_ID}` });

    const started = await cli("start", SERVER_ID);
    assert.equal(started.code, 0);
    assert.match((started.out[0] as { request_id: string }).request_id, /^[0-9a-f-]{36}$/);
    const status = await cli("status", SERVER_ID);
    assert.equal((status.out[0] as { state: string }).state, "queued");
    assert.equal((status.out[0] as { endpoint?: unknown }).endpoint, undefined);

    assert.deepEqual(fake.mutations.map(([, mutation]) => mutation.operation), ["create", "stop", "start"]);
  });
});

test("CLI reuses request IDs and reports control errors on stderr", async () => {
  await withCli(async (cli, fake) => {
    const noEula = await cli("create", "one", "--request-id", "create-one");
    assert.equal(noEula.code, 1);
    assert.deepEqual(JSON.parse(noEula.err[0]!), { error: "action_required", action_required: "accept_eula" });
    assert.match(noEula.err[1]!, /--accept-eula/);

    const first = await cli("create", "one", "--accept-eula", "--request-id", "create-one");
    const replay = await cli("create", "one", "--accept-eula", "--request-id", "create-one");
    assert.deepEqual(replay.out, first.out);

    const second = await cli("create", "two", "--accept-eula", "--request-id", "create-two");
    assert.equal(second.code, 1);
    assert.deepEqual(JSON.parse(second.err[0]!), { error: "capacity_unavailable" });

    const reused = await cli("stop", SERVER_ID, "--request-id", "create-one");
    assert.deepEqual(JSON.parse(reused.err[0]!), { error: "idempotency_key_reused" });

    const missing = await cli("status", "22e65178-a174-4ef3-8434-18765925c08f");
    assert.deepEqual(JSON.parse(missing.err[0]!), { error: "server_not_found" });
    assert.equal(fake.mutations.length, 1);
  });
});

test("CLI validates usage and credentials before calling the control API", async () => {
  await withCli(async (cli, fake) => {
    for (const argv of [[], ["create"], ["delete", SERVER_ID], ["status", SERVER_ID, "--wait"],
      ["start", SERVER_ID, "extra"], ["stop", SERVER_ID, "--unknown"]]) {
      const result = await cli(...argv);
      assert.equal(result.code, 2, argv.join(" "));
      assert.match(result.err[0]!, /^usage:/);
    }
    assert.equal(fake.mutations.length, 0);
  });

  await withCli(async (cli) => {
    const result = await cli("status", SERVER_ID);
    assert.equal(result.code, 2);
    assert.deepEqual(JSON.parse(result.err[0]!), { error: "missing_machine_token" });
  }, {});

  await withCli(async (cli) => {
    const result = await cli("status", SERVER_ID);
    assert.equal(result.code, 1);
    assert.deepEqual(JSON.parse(result.err[0]!), { error: "unauthorized" });
  }, { CLOUD_MACHINE_TOKEN: "wrong" });

  const unreachable = await runCli(["status", SERVER_ID], { env: { CLOUD_MACHINE_TOKEN: TOKEN,
    CLOUD_CONTROL_URL: "http://127.0.0.1:1" }, stdout: () => undefined, stderr: () => undefined });
  assert.equal(unreachable, 1);
});
