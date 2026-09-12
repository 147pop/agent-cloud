import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import pg from "pg";
import { ControlStore } from "../src/database.js";
import { Reconciler, type Mutation, type Runtime, type RuntimeObservation, type ServerRecord } from "../src/lifecycle.js";

class FakeRuntime implements Runtime {
  public readonly resources = new Map<string, RuntimeObservation>();
  public creates = 0;
  public starts = 0;
  public stops = 0;
  public crashAfterCreate = false;
  public beforeStart: (() => Promise<void>) | undefined;
  public beforeObserve: (() => Promise<void>) | undefined;
  public constructor(private readonly check: () => Promise<void>) {}
  public async observe(server: ServerRecord): Promise<RuntimeObservation> {
    await this.check();
    const observation = this.resources.get(server.id) ?? { state: "absent" as const };
    await this.beforeObserve?.();
    return observation;
  }
  public async create(server: ServerRecord): Promise<void> {
    await this.check();
    if (!this.resources.has(server.id)) {
      this.resources.set(server.id, { state: "stopped" });
      this.creates++;
    }
    if (this.crashAfterCreate) {
      this.crashAfterCreate = false;
      throw new Error("control_crashed_after_create");
    }
  }
  public async start(server: ServerRecord): Promise<void> {
    await this.check();
    await this.beforeStart?.();
    this.resources.set(server.id, { state: "ready", endpoint: { host: "game.invalid", port: 25565 } });
    this.starts++;
  }
  public async stop(server: ServerRecord): Promise<void> {
    await this.check();
    this.resources.set(server.id, { state: "stopping" });
    this.stops++;
  }
}

test("durable desired state converges through effects, restart and changed intent", async (t) => {
  const connectionString = process.env.TEST_DATABASE_URL;
  assert.ok(connectionString, "TEST_DATABASE_URL must point to a disposable test database");
  const schema = `test_${randomUUID().replaceAll("-", "")}`;
  const admin = new pg.Pool({ connectionString });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const options = { connectionString, options: `-c search_path=${schema}`, application_name: schema };
  const inspection = new pg.Pool({ ...options, application_name: `${schema}_inspection` });
  let store = new ControlStore(new pg.Pool(options));
  const token = randomUUID();
  try {
    const owner = await store.initialize(token);
    const runtime = new FakeRuntime(async () => {
      const result = await inspection.query<{ count: string }>(
        "SELECT count(*) FROM pg_stat_activity WHERE application_name = $1 AND state = 'idle in transaction'", [schema]
      );
      assert.equal(result.rows[0]!.count, "0", "no transaction may span a runtime effect");
    });
    let reconciler = new Reconciler(store, runtime);

    await t.test("intent and replay commit before effects; stop waits for actual termination", async () => {
      const accepted = await store.mutate(owner.id, "create-one", { operation: "create", name: "one" });
      assert.equal(accepted.state, "queued");
      assert.equal(runtime.creates, 0);
      assert.deepEqual(await store.mutate(owner.id, "create-one", { operation: "create", name: "one" }), accepted);
      assert.equal((await inspection.query("SELECT count(*) FROM runs WHERE server_id = $1", [accepted.server_id])).rows[0].count, "1");
      await assert.rejects(store.getServer(randomUUID(), accepted.server_id), /server_not_found/);
      await reconciler.reconcile(accepted.server_id);
      await reconciler.reconcile(accepted.server_id);
      assert.equal((await store.getServer(owner.id, accepted.server_id)).state, "provisioning");
      await reconciler.reconcile(accepted.server_id);
      const running = await store.getServer(owner.id, accepted.server_id);
      assert.equal(running.state, "running");
      assert.equal(running.generation, running.observed_generation);
      assert.deepEqual(running.endpoint, { host: "game.invalid", port: 25565 });
      await store.mutate(owner.id, "stop-one", { operation: "stop", server_id: accepted.server_id });
      await reconciler.reconcile(accepted.server_id);
      await reconciler.reconcile(accepted.server_id);
      assert.equal((await store.getServer(owner.id, accepted.server_id)).state, "stopping");
      assert.equal((await inspection.query("SELECT count(*) FROM runs WHERE server_id = $1 AND finished_at IS NULL", [accepted.server_id])).rows[0].count, "1");
      runtime.resources.set(accepted.server_id, { state: "stopped" });
      await reconciler.reconcile(accepted.server_id);
      assert.equal((await store.getServer(owner.id, accepted.server_id)).state, "stopped");
      await store.mutate(owner.id, "restart-one", { operation: "start", server_id: accepted.server_id });
      await reconciler.reconcile(accepted.server_id);
      await reconciler.reconcile(accepted.server_id);
      assert.equal((await store.getServer(owner.id, accepted.server_id)).world_identity, running.world_identity);
      assert.equal((await inspection.query("SELECT count(*) FROM runs WHERE server_id = $1", [accepted.server_id])).rows[0].count, "2");
      assert.equal(runtime.creates, 1);
    });

    await t.test("a new control process observes an effect completed before a crash", async () => {
      const accepted = await store.mutate(owner.id, "create-recovery", { operation: "create", name: "recovery" });
      runtime.crashAfterCreate = true;
      await assert.rejects(reconciler.reconcile(accepted.server_id), /control_crashed_after_create/);
      const creates = runtime.creates;
      await store.close();
      store = new ControlStore(new pg.Pool(options));
      await store.initialize(token);
      reconciler = new Reconciler(store, runtime);
      await reconciler.reconcile(accepted.server_id);
      await reconciler.reconcile(accepted.server_id);
      assert.equal(runtime.creates, creates);
      assert.equal((await store.getServer(owner.id, accepted.server_id)).state, "running");
      assert.deepEqual(await store.mutate(owner.id, "create-recovery", { operation: "create", name: "recovery" }), accepted);
      const events = await inspection.query("SELECT payload FROM events WHERE server_id = $1", [accepted.server_id]);
      assert.ok(events.rows.every(row => row.payload.request_id === "create-recovery"));
    });

    await t.test("a stop accepted during an older start converges to stopped", async () => {
      const accepted = await store.mutate(owner.id, "create-race", { operation: "create", name: "race" });
      await reconciler.reconcile(accepted.server_id);
      runtime.beforeStart = async () => {
        await store.mutate(owner.id, "stop-race", { operation: "stop", server_id: accepted.server_id });
      };
      await reconciler.reconcile(accepted.server_id);
      runtime.beforeStart = undefined;
      assert.equal((await store.getServer(owner.id, accepted.server_id)).desired_state, "stopped");
      await reconciler.reconcile(accepted.server_id);
      assert.equal(runtime.resources.get(accepted.server_id)!.state, "stopping");
      runtime.resources.set(accepted.server_id, { state: "stopped" });
      await reconciler.reconcile(accepted.server_id);
      const stopped = await store.getServer(owner.id, accepted.server_id);
      assert.equal(stopped.state, "stopped");
      assert.equal(stopped.generation, stopped.observed_generation);
      assert.equal(stopped.last_request_id, "stop-race");
    });

    await t.test("a stale readiness observation cannot overwrite a newer stop intent", async () => {
      const accepted = await store.mutate(owner.id, "create-observation", { operation: "create", name: "observation" });
      await reconciler.reconcile(accepted.server_id);
      await reconciler.reconcile(accepted.server_id);
      await reconciler.reconcile(accepted.server_id);
      runtime.beforeObserve = async () => {
        await store.mutate(owner.id, "stop-observation", { operation: "stop", server_id: accepted.server_id });
      };
      await reconciler.reconcile(accepted.server_id);
      runtime.beforeObserve = undefined;
      const server = await store.getServer(owner.id, accepted.server_id);
      assert.equal(server.state, "stopping");
      assert.ok(server.generation > server.observed_generation);
      await reconciler.reconcile(accepted.server_id);
      assert.equal(runtime.resources.get(accepted.server_id)!.state, "stopping");
    });

    await t.test("one failed server does not prevent another from making progress", async () => {
      await store.mutate(owner.id, "create-failing", { operation: "create", name: "failing" });
      const other = await store.mutate(owner.id, "create-independent", { operation: "create", name: "independent" });
      runtime.crashAfterCreate = true;
      await assert.rejects(reconciler.tick(), AggregateError);
      assert.ok(runtime.resources.has(other.server_id));
    });

    await t.test("TES-70: concurrent mutations and controllers produce one lifecycle effect", async () => {
      const secondStore = new ControlStore(new pg.Pool(options));
      const secondReconciler = new Reconciler(secondStore, runtime);
      const baseline = { creates: runtime.creates, starts: runtime.starts, stops: runtime.stops };
      async function concurrentMutation(key: string, mutation: Mutation) {
        const results = await Promise.all(Array.from({ length: 20 }, (_, i) =>
          (i % 2 === 0 ? store : secondStore).mutate(owner.id, key, mutation)
        ));
        for (const result of results) assert.deepEqual(result, results[0]);
        return results[0]!;
      }
      async function concurrentReconciliation(serverId: string) {
        await Promise.all(Array.from({ length: 10 }, (_, i) =>
          (i % 2 === 0 ? reconciler : secondReconciler).reconcile(serverId)
        ));
      }
      try {
        const accepted = await concurrentMutation("concurrent-create", { operation: "create", name: "concurrent" });
        for (let i = 0; i < 3; i++) await concurrentReconciliation(accepted.server_id);
        assert.equal((await store.getServer(owner.id, accepted.server_id)).state, "running");
        assert.equal(runtime.creates - baseline.creates, 1);
        assert.equal(runtime.starts - baseline.starts, 1);
        await concurrentMutation("concurrent-stop", { operation: "stop", server_id: accepted.server_id });
        await concurrentReconciliation(accepted.server_id);
        assert.equal(runtime.stops - baseline.stops, 1);
        runtime.resources.set(accepted.server_id, { state: "stopped" });
        await concurrentReconciliation(accepted.server_id);
        await concurrentMutation("concurrent-start", { operation: "start", server_id: accepted.server_id });
        for (let i = 0; i < 2; i++) await concurrentReconciliation(accepted.server_id);
        assert.equal(runtime.starts - baseline.starts, 2);
        const server = await store.getServer(owner.id, accepted.server_id);
        assert.equal(server.generation, 3);
        assert.equal(server.state, "running");
        assert.equal((await inspection.query("SELECT count(*) FROM runs WHERE server_id = $1", [server.id])).rows[0].count, "2");
        assert.equal((await inspection.query("SELECT count(*) FROM runs WHERE server_id = $1 AND finished_at IS NULL", [server.id])).rows[0].count, "1");
        assert.equal((await inspection.query("SELECT count(*) FROM events WHERE server_id = $1 AND event_type = 'intent_recorded'", [server.id])).rows[0].count, "3");
        await assert.rejects(secondStore.mutate(owner.id, "concurrent-create", { operation: "create", name: "changed" }),
          { code: "idempotency_key_reused", status: 409 });
        await assert.rejects(secondStore.mutate(owner.id, "concurrent-create", { operation: "stop", server_id: server.id }),
          { code: "idempotency_key_reused", status: 409 });
        assert.deepEqual(await secondStore.mutate(owner.id, "concurrent-create", { operation: "create", name: "concurrent" }), accepted);
      } finally {
        await secondStore.close();
      }
    });
  } finally {
    await store.close();
    await inspection.end();
    await admin.query(`DROP SCHEMA ${schema} CASCADE`);
    await admin.end();
  }
});
