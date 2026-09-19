import type { IncomingMessage, ServerResponse } from "node:http";

import { parseBearerToken, type Principal } from "./auth.js";
import type { ControlStore } from "./database.js";
import { ControlError } from "./lifecycle.js";

type ControlApi = Pick<ControlStore, "authenticate" | "mutate" | "getServer">;

const MAX_JSON_BYTES = 16 * 1024;
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

function sendJson(
  response: ServerResponse,
  statusCode: number,
  body: unknown
): void {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(body));
}

async function requirePrincipal(
  request: IncomingMessage,
  response: ServerResponse,
  authenticator: Pick<ControlApi, "authenticate">
): Promise<Principal | null> {
  const token = parseBearerToken(request.headers.authorization);
  const principal = token === null ? null : await authenticator.authenticate(token);
  if (principal === null) {
    response.setHeader("www-authenticate", "Bearer");
    sendJson(response, 401, { error: "unauthorized" });
  }
  return principal;
}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const contentType = request.headers["content-type"]?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") throw new ControlError("unsupported_media_type", 415);
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_JSON_BYTES) throw new ControlError("request_too_large", 413);
    chunks.push(buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new ControlError("invalid_json", 400);
  }
}

function parseCreateRequest(body: unknown): { client_request_id: string; name: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new ControlError("invalid_request", 400);
  }
  const input = body as Record<string, unknown>;
  if (typeof input.client_request_id !== "string" || typeof input.name !== "string") {
    throw new ControlError("invalid_request", 400);
  }
  if (input.eula_accepted === undefined || input.eula_accepted === false) {
    throw new ControlError("action_required", 409);
  }
  if (input.eula_accepted !== true) throw new ControlError("invalid_request", 400);
  return { client_request_id: input.client_request_id, name: input.name };
}

function parseLifecycleRequest(body: unknown): { client_request_id: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body) ||
      typeof (body as Record<string, unknown>).client_request_id !== "string") {
    throw new ControlError("invalid_request", 400);
  }
  return { client_request_id: (body as { client_request_id: string }).client_request_id };
}

function sendError(response: ServerResponse, error: unknown): void {
  if (error instanceof ControlError) {
    sendJson(response, error.status, error.code === "action_required" ?
      { error: error.code, action_required: "accept_eula" } : { error: error.code });
    return;
  }
  sendJson(response, 500, { error: "internal_error" });
}

export function handleRequest(
  request: IncomingMessage,
  response: ServerResponse
): void {
  if (request.method === "GET" && request.url === "/healthz") {
    sendJson(response, 200, { service: "cloud-control", status: "ok" });
    return;
  }

  sendJson(response, 404, { error: "not_found" });
}

export function createRequestHandler(control: ControlApi) {
  return async (request: IncomingMessage, response: ServerResponse): Promise<void> => {
    try {
      const path = new URL(request.url ?? "/", "http://localhost").pathname;
      if (request.method === "GET" && path === "/healthz") {
        sendJson(response, 200, { service: "cloud-control", status: "ok" });
        return;
      }

      if (request.method === "GET" && path === "/v1/whoami") {
        const principal = await requirePrincipal(request, response, control);
        if (principal === null) return;
        sendJson(response, 200, { id: principal.id, subject: principal.subject });
        return;
      }

      if (request.method === "POST" && path === "/v1/servers") {
        const principal = await requirePrincipal(request, response, control);
        if (principal === null) return;
        const input = parseCreateRequest(await readJson(request));
        const accepted = await control.mutate(principal.id, input.client_request_id, {
          operation: "create", name: input.name, eula_accepted: true
        });
        sendJson(response, 202, accepted);
        return;
      }

      const lifecycle = request.method === "POST" ?
        /^\/v1\/servers\/([^/]+)\/(start|stop)$/.exec(path) : null;
      if (lifecycle !== null) {
        const principal = await requirePrincipal(request, response, control);
        if (principal === null) return;
        const serverId = lifecycle[1]!;
        if (!UUID.test(serverId)) throw new ControlError("invalid_server_id", 400);
        const input = parseLifecycleRequest(await readJson(request));
        const accepted = await control.mutate(principal.id, input.client_request_id, {
          operation: lifecycle[2] as "start" | "stop", server_id: serverId
        });
        sendJson(response, 202, accepted);
        return;
      }

      const match = request.method === "GET" ? /^\/v1\/servers\/([^/]+)$/.exec(path) : null;
      if (match !== null) {
        const principal = await requirePrincipal(request, response, control);
        if (principal === null) return;
        const serverId = match[1]!;
        if (!UUID.test(serverId)) throw new ControlError("invalid_server_id", 400);
        const server = await control.getServer(principal.id, serverId);
        sendJson(response, 200, {
          server_id: server.id,
          name: server.logical_name,
          state: server.state,
          allocation_path: "cold",
          status_url: `/v1/servers/${server.id}`,
          ...(server.state === "running" && server.endpoint !== null ?
            { endpoint: server.endpoint } : {})
        });
        return;
      }

      sendJson(response, 404, { error: "not_found" });
    } catch (error) {
      sendError(response, error);
    }
  };
}
