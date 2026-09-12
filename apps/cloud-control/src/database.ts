import { createHash } from "node:crypto";

import pg from "pg";

import { authenticateMachineToken, bootstrapOperator, type Principal } from "./auth.js";
import { migrate } from "./migrations.js";

const { Pool } = pg;

export interface IdempotencyRecord {
  readonly operation: string;
  readonly requestDigest: Buffer;
  readonly responseStatus: number | null;
  readonly responseBody: unknown;
}

export class ControlStore {
  public constructor(private readonly pool: pg.Pool) {}

  public static fromEnvironment(environment: NodeJS.ProcessEnv): ControlStore {
    const host = requireValue(environment, "DATABASE_HOST");
    const port = Number(environment.DATABASE_PORT ?? "5432");
    if (!Number.isInteger(port) || port < 1 || port > 65_535) {
      throw new Error("DATABASE_PORT must be an integer between 1 and 65535");
    }
    return new ControlStore(new Pool({
      host,
      port,
      database: requireValue(environment, "DATABASE_NAME"),
      user: requireValue(environment, "DATABASE_USER"),
      password: requireValue(environment, "DATABASE_PASSWORD"),
      max: 10
    }));
  }

  public async initialize(machineToken: string): Promise<Principal> {
    const client = await this.pool.connect();
    try {
      await migrate(client);
      return await bootstrapOperator(client, machineToken);
    } finally {
      client.release();
    }
  }

  public authenticate(token: string): Promise<Principal | null> {
    return authenticateMachineToken(this.pool, token);
  }

  public async assertServerOwnership(principalId: string, serverId: string): Promise<void> {
    const result = await this.pool.query(
      "SELECT 1 FROM servers WHERE id = $1 AND principal_id = $2",
      [serverId, principalId]
    );
    if (result.rowCount !== 1) throw new Error("server_not_found");
  }

  public async claimIdempotencyKey(
    principalId: string,
    clientRequestId: string,
    operation: string,
    requestBody: string
  ): Promise<{ claimed: boolean; record: IdempotencyRecord }> {
    const requestDigest = createHash("sha256").update(requestBody).digest();
    const inserted = await this.pool.query(
      `INSERT INTO idempotency_keys
         (principal_id, client_request_id, operation, request_digest)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT DO NOTHING`,
      [principalId, clientRequestId, operation, requestDigest]
    );
    const result = await this.pool.query<{
      operation: string;
      request_digest: Buffer;
      response_status: number | null;
      response_body: unknown;
    }>(
      `SELECT operation, request_digest, response_status, response_body
         FROM idempotency_keys
        WHERE principal_id = $1 AND client_request_id = $2`,
      [principalId, clientRequestId]
    );
    const row = result.rows[0];
    if (row === undefined) throw new Error("idempotency claim disappeared");
    if (row.operation !== operation || !row.request_digest.equals(requestDigest)) {
      throw new Error("idempotency_key_reused");
    }
    return {
      claimed: inserted.rowCount === 1,
      record: {
        operation: row.operation,
        requestDigest: row.request_digest,
        responseStatus: row.response_status,
        responseBody: row.response_body
      }
    };
  }

  public async completeIdempotencyKey(
    principalId: string,
    clientRequestId: string,
    responseStatus: number,
    responseBody: unknown
  ): Promise<void> {
    const result = await this.pool.query(
      `UPDATE idempotency_keys
          SET response_status = $3, response_body = $4, completed_at = now()
        WHERE principal_id = $1
          AND client_request_id = $2
          AND completed_at IS NULL`,
      [principalId, clientRequestId, responseStatus, responseBody]
    );
    if (result.rowCount !== 1) throw new Error("idempotency_key_not_pending");
  }

  public async close(): Promise<void> {
    await this.pool.end();
  }
}

function requireValue(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name];
  if (value === undefined || value.length === 0) throw new Error(`${name} is required`);
  return value;
}
