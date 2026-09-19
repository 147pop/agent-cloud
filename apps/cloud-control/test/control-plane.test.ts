import assert from "node:assert/strict";
import test from "node:test";

import { assertFreeSpace } from "../src/database.js";
import { digestMachineToken, parseBearerToken, validateMachineToken } from "../src/auth.js";
import { migrations } from "../src/migrations.js";

test("machine tokens are represented by a stable SHA-256 digest", () => {
  const token = "a-private-machine-token-value";
  const digest = digestMachineToken(token);
  assert.equal(digest.length, 32);
  assert.equal(digestMachineToken(token).equals(digest), true);
  assert.equal(digest.includes(Buffer.from(token)), false);
});

test("machine token input is explicit and has a minimum size", () => {
  assert.throws(() => validateMachineToken("shared-development"), /at least 20 bytes/);
  assert.doesNotThrow(() => validateMachineToken("operator-owned-token-123"));
  assert.equal(parseBearerToken("Bearer operator-owned-token-123"), "operator-owned-token-123");
  assert.equal(parseBearerToken("bearer operator-owned-token-123"), null);
  assert.equal(parseBearerToken(undefined), null);
});

test("minimum schema encodes ownership, active-run and durable idempotency constraints", () => {
  const sql = migrations.map((migration) => migration.sql).join("\n");
  for (const table of [
    "principals", "machine_tokens", "servers", "runs", "idempotency_keys", "events"
  ]) {
    assert.match(sql, new RegExp(`CREATE TABLE ${table}`));
  }
  assert.match(sql, /principal_id uuid NOT NULL REFERENCES principals/);
  assert.match(sql, /runs_one_active_per_server/);
  assert.match(sql, /WHERE state IN \('queued', 'provisioning', 'running', 'stopping'\)/);
  assert.match(sql, /PRIMARY KEY \(principal_id, client_request_id\)/);
  assert.match(sql, /world_identity text NOT NULL UNIQUE/);
  assert.match(sql, /FOREIGN KEY \(server_id, principal_id\) REFERENCES servers\(id, principal_id\)/);
  assert.equal(migrations[0]?.name, "minimum_control_plane");
  assert.doesNotMatch(sql, /docker/i);
});

test("storage reserve rejects creation below the free-space boundary", async () => {
  const stat = async () => ({ bavail: 1024, bsize: 4096 });
  await assert.doesNotReject(assertFreeSpace(null, stat));
  await assert.doesNotReject(assertFreeSpace({ path: "/data", minFreeBytes: 4 * 1024 * 1024 }, stat));
  await assert.rejects(assertFreeSpace({ path: "/data", minFreeBytes: 4 * 1024 * 1024 + 1 }, stat),
    { code: "insufficient_storage", status: 507 });
});
