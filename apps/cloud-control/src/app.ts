import type { IncomingMessage, ServerResponse } from "node:http";

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
