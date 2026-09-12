import assert from "node:assert/strict";
import { fork } from "node:child_process";
import { randomUUID } from "node:crypto";
import test from "node:test";
import pg from "pg";
import { ControlStore } from "../src/database.js";
import type { Runtime, RuntimeObservation } from "../src/lifecycle.js";
import type { EffectMessage } from "./fixtures/reconcile-process.js";

test("TES-71: killed control processes recover every external-effect boundary", async (t) => {
  const connectionString = process.env.TEST_DATABASE_URL;
  assert.ok(connectionString, "TEST_DATABASE_URL must point to a disposable test database");
  const schema = `test_${randomUUID().replaceAll("-", "")}`;
  const admin = new pg.Pool({ connectionString });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const options = { connectionString, options: `-c search_path=${schema}` };
  const inspection = new pg.Pool(options);
  const store = new ControlStore(new pg.Pool(options));
  const resources = new Map<string, RuntimeObservation>();
  const writes = new Map<string, { create: number; start: number; stop: number }>();
  type Fault = { effect: keyof Runtime; when: "before" | "after" };

  async function runProcess(serverId: string, fault?: Fault): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      const child = fork(new URL("./fixtures/reconcile-process.js", import.meta.url), [schema, serverId],
        { stdio: ["ignore", "ignore", "pipe", "ipc"] });
      let stderr = "";
      let killed = false;
      let failure: unknown;
      child.stderr!.on("data", chunk => { stderr += String(chunk); });
      const timer = setTimeout(() => {
        failure = new Error("reconciliation process timed out");
        child.kill("SIGKILL");
      }, 15000);
      child.on("error", error => { clearTimeout(timer); reject(error); });
      child.on("message", async (message) => {
        try {
          const request = message as EffectMessage;
          assert.equal(request.type, "effect");
          assert.equal(request.server.id, serverId);
          const transactions = await inspection.query<{ count: string }>(
            "SELECT count(*) FROM pg_stat_activity WHERE application_name = $1 AND state = 'idle in transaction'",
            [`${schema}_worker`]
          );
          assert.equal(transactions.rows[0]!.count, "0");
          if (fault?.effect === request.effect && fault.when === "before") {
            killed = true;
            child.kill("SIGKILL");
            return;
          }
          const counts = writes.get(serverId) ?? { create: 0, start: 0, stop: 0 };
          writes.set(serverId, counts);
          let result: RuntimeObservation | undefined;
          if (request.effect === "observe") result = resources.get(serverId) ?? { state: "absent" };
          else if (request.effect === "create") {
            assert.equal(resources.has(serverId), false, "creation effect must not be repeated");
            resources.set(serverId, { state: "stopped" });
            counts.create++;
          } else if (request.effect === "start") {
            assert.equal(resources.get(serverId)?.state, "stopped", "start effect must not be repeated");
            resources.set(serverId, { state: "ready", endpoint: { host: "game.invalid", port: 25565 } });
            counts.start++;
          } else {
            assert.equal(resources.get(serverId)?.state, "ready", "stop effect must not be repeated");
            resources.set(serverId, { state: "stopped" });
            counts.stop++;
          }
          if (fault?.effect === request.effect && fault.when === "after") {
            killed = true;
            child.kill("SIGKILL");
          } else child.send({ result });
        } catch (error) {
          failure = error;
          child.kill("SIGKILL");
        }
      });
      child.on("exit", (code, signal) => {
        clearTimeout(timer);
        if (failure) reject(failure);
        else if (fault && (!killed || signal !== "SIGKILL")) reject(new Error(`fault was not exercised: ${stderr}`));
        else if (!fault && code !== 0) reject(new Error(`reconciliation failed: ${stderr}`));
        else resolve();
      });
    });
  }

  try {
    const owner = await store.initialize(randomUUID());
    for (const operation of ["create", "start", "stop"] as const) {
      for (const effect of ["observe", operation] as const) {
        for (const when of ["before", "after"] as const) {
          await t.test(`${operation}: killed ${when} ${effect}`, async () => {
            const name = `crash-${operation}-${effect}-${when}`;
            const created = await store.mutate(owner.id, `${name}-create`, { operation: "create", name });
            const id = created.server_id;
            if (operation !== "create") {
              for (let i = 0; i < 3; i++) await runProcess(id);
              if (operation === "start") {
                await store.mutate(owner.id, `${name}-setup-stop`, { operation: "stop", server_id: id });
                for (let i = 0; i < 2; i++) await runProcess(id);
              }
            }
            const requestId = operation === "create" ? `${name}-create` : `${name}-request`;
            const mutation = operation === "create" ? { operation, name } : { operation, server_id: id };
            const accepted = await store.mutate(owner.id, requestId, mutation);
            const before = await store.getServer(owner.id, id);
            await runProcess(id, { effect, when });
            for (let i = 0; i < 4; i++) {
              await runProcess(id);
              const active = await inspection.query<{ count: string }>(
                "SELECT count(*) FROM runs WHERE server_id = $1 AND finished_at IS NULL", [id]
              );
              assert.ok(Number(active.rows[0]!.count) <= 1);
            }
            const after = await store.getServer(owner.id, id);
            assert.equal(after.state, operation === "stop" ? "stopped" : "running");
            assert.equal(after.generation, after.observed_generation);
            assert.equal(after.world_identity, before.world_identity);
            assert.equal(after.last_request_id, requestId);
            assert.deepEqual(await store.mutate(owner.id, requestId, mutation), accepted);
            assert.deepEqual(writes.get(id), { create: 1, start: operation === "start" ? 2 : 1,
              stop: operation === "create" ? 0 : 1 });
            const event = await inspection.query(
              "SELECT id FROM events WHERE server_id = $1 AND payload->>'request_id' = $2", [id, requestId]
            );
            assert.ok(event.rowCount! > 0);
          });
        }
      }
    }
  } finally {
    await store.close();
    await inspection.end();
    await admin.query(`DROP SCHEMA ${schema} CASCADE`);
    await admin.end();
  }
});
