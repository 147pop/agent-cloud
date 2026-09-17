import { request as httpRequest } from "node:http";

import type { Runtime, RuntimeObservation, ServerRecord } from "./lifecycle.js";

export interface DockerContainerSummary {
  Id: string;
  Names: string[];
  Labels: Record<string, string>;
}

export interface DockerContainer {
  Id: string;
  Name: string;
  Config: {
    Labels: Record<string, string>;
  };
  Mounts: Array<{
    Destination: string;
    Type: string;
  }>;
  State: {
    Status: string;
    Running: boolean;
    Restarting: boolean;
    Health?: { Status: string };
  };
}

export interface DockerAPI {
  listContainers(project: string, service: string): Promise<DockerContainerSummary[]>;
  inspectContainer(id: string): Promise<DockerContainer | null>;
  startContainer(id: string): Promise<void>;
  stopContainer(id: string, timeoutSeconds: number): Promise<void>;
}

export class DockerError extends Error {
  public constructor(public readonly status: number, public readonly body: string) {
    super(`docker_http_${status}`);
  }
}

class UnixSocketDockerAPI implements DockerAPI {
  public constructor(
    private readonly socketPath: string,
    private readonly apiVersion: string
  ) {}

  private async request<T>(method: "GET" | "POST", path: string, timeoutMs = 15_000): Promise<T | undefined> {
    return new Promise((resolve, reject) => {
      const request = httpRequest({
        socketPath: this.socketPath,
        path: `/${this.apiVersion}${path}`,
        method,
        headers: { accept: "application/json" }
      }, response => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk: Buffer) => chunks.push(chunk));
        response.on("error", reject);
        response.on("end", () => {
          const body = Buffer.concat(chunks).toString("utf8");
          const status = response.statusCode ?? 500;
          if (status >= 400) {
            reject(new DockerError(status, body));
            return;
          }
          if (body.length === 0) {
            resolve(undefined);
            return;
          }
          try { resolve(JSON.parse(body) as T); }
          catch (error) { reject(error); }
        });
      });
      request.setTimeout(timeoutMs, () => request.destroy(new Error("docker_engine_timeout")));
      request.on("error", reject);
      request.end();
    });
  }

  public async listContainers(project: string, service: string): Promise<DockerContainerSummary[]> {
    const filters = encodeURIComponent(JSON.stringify({
      label: [`com.docker.compose.project=${project}`, `com.docker.compose.service=${service}`]
    }));
    return await this.request<DockerContainerSummary[]>("GET", `/containers/json?all=true&filters=${filters}`) ?? [];
  }

  public async inspectContainer(id: string): Promise<DockerContainer | null> {
    try { return await this.request<DockerContainer>("GET", `/containers/${encodeURIComponent(id)}/json`) ?? null; }
    catch (error) {
      if (error instanceof DockerError && error.status === 404) return null;
      throw error;
    }
  }

  public async startContainer(id: string): Promise<void> {
    await this.request("POST", `/containers/${encodeURIComponent(id)}/start`);
  }

  public async stopContainer(id: string, timeoutSeconds: number): Promise<void> {
    await this.request("POST", `/containers/${encodeURIComponent(id)}/stop?t=${timeoutSeconds}`,
      Math.max(15_000, (timeoutSeconds + 15) * 1_000));
  }
}

export interface DockerRuntimeOptions {
  readonly project: string;
  readonly service: string;
  readonly containerName: string;
  readonly gameHost: string;
  readonly gamePort: number;
  readonly stopTimeoutSeconds: number;
}

export class DockerRuntimeError extends Error {
  public constructor(public readonly code: string) {
    super(code);
  }
}

export class DockerRuntime implements Runtime {
  public constructor(
    private readonly api: DockerAPI,
    private readonly options: DockerRuntimeOptions
  ) {}

  public static fromEnvironment(environment: NodeJS.ProcessEnv): DockerRuntime {
    const gamePort = integerValue(environment.CLOUD_GAME_PORT ?? "25565", "CLOUD_GAME_PORT");
    const stopTimeoutSeconds = integerValue(environment.CLOUD_STOP_TIMEOUT_SECONDS ?? "120", "CLOUD_STOP_TIMEOUT_SECONDS");
    return new DockerRuntime(
      new UnixSocketDockerAPI(environment.DOCKER_SOCKET_PATH ?? "/var/run/docker.sock", environment.DOCKER_API_VERSION ?? "v1.45"),
      {
        project: environment.CLOUD_COMPOSE_PROJECT ?? "cloud",
        service: environment.CLOUD_COMPOSE_SERVICE ?? "game-1",
        containerName: environment.CLOUD_GAME_CONTAINER_NAME ?? "cloud-game-1",
        gameHost: environment.CLOUD_GAME_HOST ?? "127.0.0.1",
        gamePort,
        stopTimeoutSeconds
      }
    );
  }

  private async container(): Promise<DockerContainer | null> {
    const summaries = await this.api.listContainers(this.options.project, this.options.service);
    if (summaries.length === 0) return null;
    if (summaries.length !== 1) throw new DockerRuntimeError("docker_game_identity_ambiguous");
    const container = await this.api.inspectContainer(summaries[0]!.Id);
    if (container === null) return null;
    this.verifyIdentity(container);
    return container;
  }

  private verifyIdentity(container: DockerContainer): void {
    if (container.Name !== `/${this.options.containerName}` ||
        container.Config.Labels["com.docker.compose.project"] !== this.options.project ||
        container.Config.Labels["com.docker.compose.service"] !== this.options.service ||
        !container.Mounts.some(mount => mount.Destination === "/data" && mount.Type === "volume")) {
      throw new DockerRuntimeError("docker_game_identity_mismatch");
    }
  }

  private requireContainer(container: DockerContainer | null): DockerContainer {
    if (container === null) {
      throw new DockerRuntimeError("docker_game_missing: run infra/compose/setup.sh to recreate game-1");
    }
    return container;
  }

  public async observe(_server: ServerRecord): Promise<RuntimeObservation> {
    const container = await this.container();
    if (container === null) return { state: "absent" };
    if (container.State.Status === "removing") return { state: "stopping" };
    if (container.State.Running || container.State.Restarting) {
      return container.State.Health?.Status === "healthy" ?
        { state: "ready", endpoint: { host: this.options.gameHost, port: this.options.gamePort } } :
        { state: "starting" };
    }
    if (["created", "exited", "dead"].includes(container.State.Status)) return { state: "stopped" };
    return { state: "starting" };
  }

  public async create(_server: ServerRecord): Promise<void> {
    this.requireContainer(await this.container());
  }

  public async start(_server: ServerRecord): Promise<void> {
    const container = this.requireContainer(await this.container());
    if (container.State.Running || container.State.Restarting) return;
    if (container.State.Status === "removing") throw new DockerRuntimeError("docker_game_stopping");
    await this.api.startContainer(container.Id);
  }

  public async stop(_server: ServerRecord): Promise<void> {
    const container = await this.container();
    if (container === null || (!container.State.Running && !container.State.Restarting)) return;
    await this.api.stopContainer(container.Id, this.options.stopTimeoutSeconds);
    const stopped = await this.api.inspectContainer(container.Id);
    if (stopped?.State.Running === true || stopped?.State.Restarting === true) {
      throw new DockerRuntimeError("docker_game_stop_incomplete");
    }
  }
}

function integerValue(value: string, name: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65_535) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}
