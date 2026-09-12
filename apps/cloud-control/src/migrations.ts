import type { PoolClient } from "pg";

export interface Migration {
  readonly version: number;
  readonly name: string;
  readonly sql: string;
}

export const migrations: readonly Migration[] = [
  {
    version: 1,
    name: "minimum_control_plane",
    sql: `
CREATE TABLE principals (
  id uuid PRIMARY KEY,
  subject text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE machine_tokens (
  id uuid PRIMARY KEY,
  principal_id uuid NOT NULL REFERENCES principals(id) ON DELETE CASCADE,
  token_digest bytea NOT NULL UNIQUE,
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CHECK (octet_length(token_digest) = 32)
);

CREATE TABLE servers (
  id uuid PRIMARY KEY,
  principal_id uuid NOT NULL REFERENCES principals(id),
  logical_name text NOT NULL,
  recipe_id text NOT NULL,
  profile_id text NOT NULL,
  world_identity text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (principal_id, logical_name),
  UNIQUE (id, principal_id)
);

CREATE TABLE runs (
  id uuid PRIMARY KEY,
  server_id uuid NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
  state text NOT NULL CHECK (state IN (
    'queued', 'provisioning', 'running', 'stopping', 'stopped', 'failed'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  CHECK ((state IN ('stopped', 'failed')) = (finished_at IS NOT NULL))
);

CREATE UNIQUE INDEX runs_one_active_per_server
  ON runs (server_id)
  WHERE state IN ('queued', 'provisioning', 'running', 'stopping');

CREATE TABLE idempotency_keys (
  principal_id uuid NOT NULL REFERENCES principals(id) ON DELETE CASCADE,
  client_request_id text NOT NULL,
  operation text NOT NULL,
  request_digest bytea NOT NULL,
  response_status integer,
  response_body jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  PRIMARY KEY (principal_id, client_request_id),
  CHECK (octet_length(request_digest) = 32),
  CHECK ((response_status IS NULL) = (completed_at IS NULL)),
  CHECK (response_status IS NULL OR response_status BETWEEN 100 AND 599)
);

CREATE TABLE events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  principal_id uuid NOT NULL REFERENCES principals(id),
  server_id uuid REFERENCES servers(id) ON DELETE CASCADE,
  run_id uuid REFERENCES runs(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (server_id, principal_id) REFERENCES servers(id, principal_id)
);

CREATE INDEX events_server_order ON events (server_id, id);
CREATE INDEX events_run_order ON events (run_id, id);
`
  },
  {
    version: 2,
    name: "event_run_ownership",
    sql: `
ALTER TABLE runs ADD CONSTRAINT runs_id_server_unique UNIQUE (id, server_id);
ALTER TABLE events ADD CONSTRAINT events_run_server_fk
  FOREIGN KEY (run_id, server_id) REFERENCES runs(id, server_id);
ALTER TABLE events ADD CONSTRAINT events_run_requires_server
  CHECK (run_id IS NULL OR server_id IS NOT NULL);
`
  }
];

export async function migrate(client: PoolClient): Promise<void> {
  await client.query("BEGIN");
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version integer PRIMARY KEY,
        name text NOT NULL UNIQUE,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);

    await client.query("LOCK TABLE schema_migrations IN EXCLUSIVE MODE");

    for (const migration of migrations) {
      const result = await client.query<{ version: number }>(
        "SELECT version FROM schema_migrations WHERE version = $1",
        [migration.version]
      );
      if (result.rowCount === 0) {
        await client.query(migration.sql);
        await client.query(
          "INSERT INTO schema_migrations (version, name) VALUES ($1, $2)",
          [migration.version, migration.name]
        );
      }
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  }
}
