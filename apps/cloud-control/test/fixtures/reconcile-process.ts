import assert from "node:assert/strict";
import pg from "pg";
import { ControlStore } from "../../src/database.js";
import { Reconciler, type Runtime, type RuntimeObservation, type ServerRecord } from "../../src/lifecycle.js";

export interface EffectMessage { type: "effect"; effect: keyof Runtime; server: ServerRecord }
const [schema, serverId] = process.argv.slice(2);
assert.ok(schema && /^test_[a-f0-9]{32}$/.test(schema));
assert.ok(serverId && process.send && process.env.TEST_DATABASE_URL);
const store = new ControlStore(new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL,
  options: `-c search_path=${schema}`, application_name: `${schema}_worker` }));

function effect<T>(name: keyof Runtime, server: ServerRecord): Promise<T> {
  return new Promise(resolve => {
    process.once("message", (message: { result: T }) => resolve(message.result));
    process.send!({ type: "effect", effect: name, server } satisfies EffectMessage);
  });
}
const runtime: Runtime = {
  observe: server => effect<RuntimeObservation>("observe", server),
  create: server => effect<void>("create", server),
  start: server => effect<void>("start", server),
  stop: server => effect<void>("stop", server)
};

try {
  await new Reconciler(store, runtime).reconcile(serverId);
} finally {
  await store.close();
  process.disconnect();
}
