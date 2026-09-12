import type { IncomingMessage, ServerResponse } from "node:http";

import { parseBearerToken, type Principal } from "./auth.js";

export interface Authenticator {
  authenticate(token: string): Promise<Principal | null>;
}

function sendJson(
  response: ServerResponse,
  statusCode: number,
  body: Record<string, string>
): void {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(body));
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

export function createRequestHandler(authenticator: Authenticator) {
  return async (request: IncomingMessage, response: ServerResponse): Promise<void> => {
    if (request.method === "GET" && request.url === "/healthz") {
      sendJson(response, 200, { service: "cloud-control", status: "ok" });
      return;
    }

    if (request.method === "GET" && request.url === "/v1/whoami") {
      const token = parseBearerToken(request.headers.authorization);
      if (token === null) {
        response.setHeader("www-authenticate", "Bearer");
        sendJson(response, 401, { error: "unauthorized" });
        return;
      }
      const principal = await authenticator.authenticate(token);
      if (principal === null) {
        response.setHeader("www-authenticate", "Bearer");
        sendJson(response, 401, { error: "unauthorized" });
        return;
      }
      sendJson(response, 200, { id: principal.id, subject: principal.subject });
      return;
    }

    sendJson(response, 404, { error: "not_found" });
  };
}
