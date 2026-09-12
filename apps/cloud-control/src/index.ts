import { createServer } from "node:http";

import { createRequestHandler } from "./app.js";
import { ControlStore } from "./database.js";

const host = process.env.HOST ?? "127.0.0.1";
const port = Number(process.env.PORT ?? "3000");

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

const machineToken = process.env.CLOUD_MACHINE_TOKEN;
if (machineToken === undefined) throw new Error("CLOUD_MACHINE_TOKEN is required");

const store = ControlStore.fromEnvironment(process.env);
await store.initialize(machineToken);

const server = createServer(createRequestHandler(store));

async function shutdown(): Promise<void> {
  server.close();
  await store.close();
}

process.once("SIGINT", () => void shutdown());
process.once("SIGTERM", () => void shutdown());

server.listen(port, host, () => {
  process.stdout.write(
    `${JSON.stringify({ event: "listening", host, port, service: "cloud-control" })}\n`
  );
});
