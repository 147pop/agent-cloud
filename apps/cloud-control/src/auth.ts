import { createHash, randomUUID } from "node:crypto";

import type { Pool, PoolClient } from "pg";

export interface Principal {
  readonly id: string;
  readonly subject: string;
}

export function digestMachineToken(token: string): Buffer {
  return createHash("sha256").update(token, "utf8").digest();
}

export function parseBearerToken(header: string | undefined): string | null {
  if (header === undefined) return null;
  const match = /^Bearer ([^\s]+)$/.exec(header);
  return match?.[1] ?? null;
}

export function validateMachineToken(token: string): void {
  if (Buffer.byteLength(token, "utf8") < 20) {
    throw new Error("CLOUD_MACHINE_TOKEN must contain at least 20 bytes");
  }
}

export async function bootstrapOperator(
  client: PoolClient,
  token: string
): Promise<Principal> {
  validateMachineToken(token);
  const digest = digestMachineToken(token);

  await client.query("BEGIN");
  try {
    const principalResult = await client.query<Principal>(
      `INSERT INTO principals (id, subject)
       VALUES ($1, 'operator')
       ON CONFLICT (subject) DO UPDATE SET subject = EXCLUDED.subject
       RETURNING id, subject`,
      [randomUUID()]
    );
    const principal = principalResult.rows[0];
    if (principal === undefined) throw new Error("operator bootstrap returned no principal");

    const tokenResult = await client.query<{ principal_id: string }>(
      `INSERT INTO machine_tokens (id, principal_id, token_digest, label)
       VALUES ($1, $2, $3, 'operator-bootstrap')
       ON CONFLICT (token_digest) DO UPDATE SET token_digest = EXCLUDED.token_digest
       RETURNING principal_id`,
      [randomUUID(), principal.id, digest]
    );
    if (tokenResult.rows[0]?.principal_id !== principal.id) {
      throw new Error("machine token is already owned by another principal");
    }

    await client.query("COMMIT");
    return principal;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  }
}

export async function authenticateMachineToken(
  pool: Pool,
  token: string
): Promise<Principal | null> {
  const result = await pool.query<Principal>(
    `SELECT p.id, p.subject
       FROM machine_tokens mt
       JOIN principals p ON p.id = mt.principal_id
      WHERE mt.token_digest = $1 AND mt.revoked_at IS NULL`,
    [digestMachineToken(token)]
  );
  return result.rows[0] ?? null;
}
