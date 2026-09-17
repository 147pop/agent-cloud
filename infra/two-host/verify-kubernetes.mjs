import assert from "node:assert/strict";
import { setTimeout } from "node:timers/promises";
import { ControlStore } from "./dist/src/database.js";
import { KubernetesRuntime } from "./dist/src/kubernetes.js";

const [action, value, requestId] = process.argv.slice(2);
const store = ControlStore.fromEnvironment(process.env);
const principal = await store.authenticate(process.env.CLOUD_MACHINE_TOKEN);
assert.ok(principal);
try {
  if (["create", "start", "stop"].includes(action)) {
    const mutation = action === "create" ? { operation: action, name: value, eula_accepted: true } : { operation: action, server_id: value };
    const accepted = await store.mutate(principal.id, requestId, mutation);
    assert.deepEqual(await store.mutate(principal.id, requestId, mutation), accepted);
    process.stdout.write(JSON.stringify(accepted));
  } else if (action === "wait") {
    const deadline = Date.now() + 600_000;
    for (;;) {
      const server = await store.getServer(principal.id, value);
      if (server.state === requestId && server.generation === server.observed_generation) {
        process.stdout.write(JSON.stringify({ id: server.id, world_identity: server.world_identity, state: server.state }));
        break;
      }
      assert.ok(Date.now() < deadline, `timed out waiting for ${requestId}; state=${server.state}`);
      await setTimeout(1000);
    }
  } else if (action === "retry") {
    const server = await store.getServer(principal.id, value);
    const runtime = KubernetesRuntime.inCluster();
    await runtime.create(server);
    await runtime.create(server);
    assert.equal((await runtime.observe(server)).state, "ready");
    process.stdout.write(JSON.stringify({ result: "passed" }));
  } else {
    throw new Error("expected create/start/stop/wait/retry");
  }
} finally {
  await store.close();
}
