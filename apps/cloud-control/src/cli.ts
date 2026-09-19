import { setTimeout as sleep } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const USAGE = `usage: cloud <command> [options]
  create <name> --accept-eula [--request-id ID] [--wait]
  start <server_id> [--request-id ID] [--wait]
  stop <server_id> [--request-id ID] [--wait]
  status <server_id>
environment: CLOUD_MACHINE_TOKEN (required), CLOUD_CONTROL_URL (default http://127.0.0.1:3000)`;

export interface CliIo {
  env: Record<string, string | undefined>;
  stdout(line: string): void;
  stderr(line: string): void;
  pollMs?: number;
}

class ResponseError extends Error {
  public constructor(public readonly body: { error?: string; action_required?: string }) {
    super(body.error);
  }
}

export async function runCli(argv: string[], io: CliIo): Promise<number> {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, options: {
      "accept-eula": { type: "boolean" }, "request-id": { type: "string" }, wait: { type: "boolean" }
    } });
  } catch {
    io.stderr(USAGE);
    return 2;
  }
  const [command, target, ...extra] = parsed.positionals;
  const { values } = parsed;
  if (command === undefined || target === undefined || extra.length > 0 ||
      !["create", "start", "stop", "status"].includes(command) ||
      (command === "status" && (values["request-id"] !== undefined || values.wait === true))) {
    io.stderr(USAGE);
    return 2;
  }
  const token = io.env.CLOUD_MACHINE_TOKEN;
  if (token === undefined || token === "") {
    io.stderr(JSON.stringify({ error: "missing_machine_token" }));
    return 2;
  }
  const base = io.env.CLOUD_CONTROL_URL ?? "http://127.0.0.1:3000";

  const request = async (path: string, body?: object): Promise<Record<string, unknown>> => {
    const response = await fetch(new URL(path, base), body === undefined ?
      { headers: { authorization: `Bearer ${token}` } } :
      { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify(body) });
    const payload = await response.json().catch(() => ({ error: `http_${response.status}` }));
    if (!response.ok) throw new ResponseError(payload as ResponseError["body"]);
    return payload as Record<string, unknown>;
  };

  try {
    const serverPath = `/v1/servers/${encodeURIComponent(target)}`;
    if (command === "status") {
      io.stdout(JSON.stringify(await request(serverPath)));
      return 0;
    }
    const clientRequestId = values["request-id"] ?? crypto.randomUUID();
    const accepted = command === "create" ?
      await request("/v1/servers", { client_request_id: clientRequestId, name: target,
        eula_accepted: values["accept-eula"] === true }) :
      await request(`${serverPath}/${command}`, { client_request_id: clientRequestId });
    io.stdout(JSON.stringify(accepted));
    if (values.wait !== true) return 0;

    // ponytail: waits without a deadline; Ctrl-C ends it, add --timeout if scripts need one.
    const wanted = command === "stop" ? "stopped" : "running";
    for (;;) {
      const status = await request(String(accepted.status_url));
      if (status.state === wanted) {
        io.stdout(JSON.stringify(status));
        return 0;
      }
      await sleep(io.pollMs ?? 1000);
    }
  } catch (error) {
    if (!(error instanceof ResponseError)) {
      io.stderr(JSON.stringify({ error: "control_unreachable", url: base }));
      return 1;
    }
    io.stderr(JSON.stringify(error.body));
    if (error.body.action_required === "accept_eula") {
      io.stderr("Accept the Minecraft EULA (https://aka.ms/MinecraftEULA) with --accept-eula.");
    }
    return 1;
  }
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await runCli(process.argv.slice(2), {
    env: process.env,
    stdout: line => process.stdout.write(`${line}\n`),
    stderr: line => process.stderr.write(`${line}\n`)
  });
}
