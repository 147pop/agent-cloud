import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { ControlStore } from "./dist/src/database.js";
import { migrations } from "./dist/src/migrations.js";

const [phase, snapshot] = process.argv.slice(2);
assert.ok(phase === "seed" || phase === "verify", "usage: node - seed | node - verify <snapshot-json>");
const pool = new pg.Pool({
  host: process.env.DATABASE_HOST,
  port: Number(process.env.DATABASE_PORT),
  database: process.env.DATABASE_NAME,
  user: process.env.DATABASE_USER,
  password: process.env.DATABASE_PASSWORD
});
const store = new ControlStore(pool);
const token = process.env.CLOUD_MACHINE_TOKEN;
assert.ok(token);

try {
  const response = await fetch("http://127.0.0.1:3000/v1/whoami", {
    headers: { authorization: `Bearer ${token}` }
  });
  assert.equal(response.status, 200);
  const principal = await response.json();
  assert.equal((await fetch("http://127.0.0.1:3000/v1/whoami")).status, 401);
  assert.equal((await fetch("http://127.0.0.1:3000/v1/whoami", {
    headers: { authorization: `Bearer ${randomUUID()}` }
  })).status, 401);

  if (phase === "seed") {
    const serverId = randomUUID();
    const requestId = `tes-66-${randomUUID()}`;
    await pool.query(
      `INSERT INTO servers (id, principal_id, logical_name, recipe_id, profile_id, world_identity)
       VALUES ($1, $2, $3, 'paper-26.2-121', 'two-player', $3)`,
      [serverId, principal.id, requestId]
    );
    await pool.query(
      "INSERT INTO runs (id, server_id, state, finished_at) VALUES ($1, $2, 'stopped', now())",
      [randomUUID(), serverId]
    );
    await pool.query(
      "INSERT INTO events (principal_id, server_id, event_type) VALUES ($1, $2, 'identity_acceptance')",
      [principal.id, serverId]
    );
    assert.equal((await store.claimIdempotencyKey(principal.id, requestId, "create", "{}")).claimed, true);
    await store.completeIdempotencyKey(principal.id, requestId, 202, { server_id: serverId });
    process.stdout.write(JSON.stringify({ principal, serverId, requestId }) + "\n");
  } else {
    const before = JSON.parse(snapshot);
    assert.deepEqual(principal, before.principal);
    await store.assertServerOwnership(principal.id, before.serverId);
    const replay = await store.claimIdempotencyKey(principal.id, before.requestId, "create", "{}");
    assert.equal(replay.claimed, false);
    assert.equal(replay.record.responseStatus, 202);
    assert.deepEqual(replay.record.responseBody, { server_id: before.serverId });
    assert.equal((await pool.query("SELECT id FROM runs WHERE server_id = $1", [before.serverId])).rowCount, 1);
    assert.equal((await pool.query("SELECT id FROM events WHERE server_id = $1", [before.serverId])).rowCount, 1);
    assert.deepEqual((await pool.query("SELECT version FROM schema_migrations ORDER BY version")).rows,
      migrations.map(({ version }) => ({ version })));
    await pool.query("DELETE FROM idempotency_keys WHERE principal_id = $1 AND client_request_id = $2", [principal.id, before.requestId]);
    await pool.query("DELETE FROM servers WHERE id = $1 AND principal_id = $2", [before.serverId, principal.id]);
    process.stdout.write(JSON.stringify({ result: "passed", identity: "preserved", records: "preserved", fixture: "removed" }) + "\n");
  }
} finally {
  await store.close();
}
