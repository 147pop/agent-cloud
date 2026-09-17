import assert from "node:assert/strict";
import test from "node:test";

import { DockerRuntime, type DockerAPI, type DockerContainer } from "../src/docker.js";
import type { ServerRecord } from "../src/lifecycle.js";

const server = {} as ServerRecord;
const options = {
  project: "cloud",
  service: "game-1",
  containerName: "cloud-game-1",
  gameHost: "127.0.0.1",
  gamePort: 25565,
  stopTimeoutSeconds: 120
} as const;

class FakeDocker implements DockerAPI {
  public container: DockerContainer | null = makeContainer("exited", false, "none");
  public starts = 0;
  public stops = 0;

  public async listContainers(_project: string, _service: string) {
    return this.container === null ? [] : [{
      Id: this.container.Id,
      Names: [this.container.Name],
      Labels: this.container.Config.Labels
    }];
  }

  public async inspectContainer(_id: string): Promise<DockerContainer | null> {
    return this.container === null ? null : structuredClone(this.container);
  }

  public async startContainer(_id: string): Promise<void> {
    this.starts++;
    this.container!.State = { Status: "running", Running: true, Restarting: false, Health: { Status: "starting" } };
  }

  public async stopContainer(_id: string, _timeoutSeconds: number): Promise<void> {
    this.stops++;
    this.container!.State = { Status: "exited", Running: false, Restarting: false, Health: { Status: "none" } };
  }
}

test("Docker runtime reports protocol readiness and the stable local endpoint", async () => {
  const api = new FakeDocker();
  const runtime = new DockerRuntime(api, options);

  assert.deepEqual(await runtime.observe(server), { state: "stopped" });
  api.container!.State = { Status: "running", Running: true, Restarting: false, Health: { Status: "starting" } };
  assert.deepEqual(await runtime.observe(server), { state: "starting" });
  api.container!.State.Health!.Status = "healthy";
  assert.deepEqual(await runtime.observe(server), {
    state: "ready",
    endpoint: { host: "127.0.0.1", port: 25565 }
  });
});

test("Docker start and stop are idempotent and stop waits for an exited container", async () => {
  const api = new FakeDocker();
  const runtime = new DockerRuntime(api, options);

  await runtime.start(server);
  await runtime.start(server);
  assert.equal(api.starts, 1);
  await runtime.stop(server);
  await runtime.stop(server);
  assert.equal(api.stops, 1);
  assert.deepEqual(await runtime.observe(server), { state: "stopped" });

  api.container!.State = { Status: "restarting", Running: false, Restarting: true, Health: { Status: "starting" } };
  await runtime.stop(server);
  assert.equal(api.stops, 2);
});

test("Docker runtime refuses missing or mismatched Compose containers", async () => {
  const missing = new FakeDocker();
  missing.container = null;
  const missingRuntime = new DockerRuntime(missing, options);
  assert.deepEqual(await missingRuntime.observe(server), { state: "absent" });
  await assert.rejects(missingRuntime.create(server), /docker_game_missing/);

  const mismatched = new FakeDocker();
  mismatched.container!.Config.Labels["com.docker.compose.service"] = "other";
  const mismatchedRuntime = new DockerRuntime(mismatched, options);
  await assert.rejects(mismatchedRuntime.start(server), /docker_game_identity_mismatch/);
});

function makeContainer(status: string, running: boolean, health: string): DockerContainer {
  return {
    Id: "container-id",
    Name: "/cloud-game-1",
    Config: {
      Labels: {
        "com.docker.compose.project": "cloud",
        "com.docker.compose.service": "game-1"
      }
    },
    Mounts: [{ Destination: "/data", Type: "volume" }],
    State: { Status: status, Running: running, Restarting: false, Health: { Status: health } }
  };
}
