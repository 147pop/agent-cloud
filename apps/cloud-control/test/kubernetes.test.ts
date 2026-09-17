import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { parse } from "yaml";

import { KubernetesError, KubernetesRuntime, type KubernetesAPI, type Resource } from "../src/kubernetes.js";
import type { ServerRecord } from "../src/lifecycle.js";

const server: ServerRecord = {
  id: "c7f4b1ea-8103-41c8-a2df-3d731335160d", principal_id: "owner", logical_name: "test",
  recipe_id: "paper-26.2-121", profile_id: "two-player", world_identity: "cloud-world-test",
  desired_state: "running", state: "queued", generation: 1, observed_generation: 0,
  last_request_id: "create-test", endpoint: null
};
const recipe = parse(readFileSync(new URL("../../../../catalog/games/minecraft-java/paper/k8s/deployment.yaml", import.meta.url), "utf8")) as Resource;

class API implements KubernetesAPI {
  public resources = new Map<string, Resource>();
  public pods: Resource[] = [];
  public failAfterCreate = false;
  public async call<T>(method: string, path: string, body?: unknown): Promise<T> {
    if (path.includes("/pods?")) return structuredClone({ items: this.pods }) as T;
    if (method === "POST") {
      const resource = structuredClone(body) as Resource;
      const key = `${path}/${resource.metadata.name}`;
      if (this.resources.has(key)) throw new KubernetesError(409);
      this.resources.set(key, resource);
      if (this.failAfterCreate) { this.failAfterCreate = false; throw new Error("lost_response"); }
      return structuredClone(resource) as T;
    }
    const resource = this.resources.get(path);
    if (resource === undefined) throw new KubernetesError(404);
    if (method === "PATCH") Object.assign(resource.spec, (body as Resource).spec);
    return structuredClone(resource) as T;
  }
  public deployment(): Resource { return [...this.resources.values()].find(item => item.kind === "Deployment")!; }
  public pod(ready: boolean, terminating = false): Resource {
    return { apiVersion: "v1", kind: "Pod", metadata: {
      name: "paper-test", ...(terminating ? { deletionTimestamp: "2026-09-12T00:00:00Z" } : {})
    }, spec: {}, status: { conditions: [{ type: "Ready", status: ready ? "True" : "False" }] } };
  }
}

test("lost Kubernetes response and repeated create preserve resources and running replicas", async () => {
  const api = new API();
  let runtime = new KubernetesRuntime(api, recipe);
  api.failAfterCreate = true;
  await assert.rejects(runtime.create(server), /lost_response/);
  runtime = new KubernetesRuntime(api, recipe);
  await runtime.create(server);
  await runtime.start(server);
  await runtime.create(server);
  assert.equal(api.resources.size, 3);
  assert.equal(api.deployment().spec.replicas, 1);
  const volume = [...api.resources.values()].find(item => item.kind === "PersistentVolumeClaim")!;
  assert.equal(volume.spec.storageClassName, "local-path-retain");
  assert.deepEqual(volume.metadata.labels, { "cloud.example/server-id": server.id, "cloud.example/world-id": server.world_identity });
});

test("endpoint waits for protocol probe; stop waits for all old pods before restart", async () => {
  const api = new API();
  const runtime = new KubernetesRuntime(api, recipe);
  await runtime.create(server);
  await runtime.start(server);
  api.pods = [api.pod(false)];
  assert.deepEqual(await runtime.observe(server), { state: "starting" });
  api.pods = [api.pod(true, true)];
  assert.deepEqual(await runtime.observe(server), { state: "starting" });
  api.pods = [api.pod(true), api.pod(false)];
  assert.deepEqual(await runtime.observe(server), { state: "starting" });
  api.pods = [api.pod(true)];
  assert.equal((await runtime.observe(server)).state, "ready");
  assert.equal((await runtime.observe(server)).endpoint?.port, 25565);
  const resourcesBefore = [...api.resources.keys()];
  await runtime.stop(server);
  assert.deepEqual(await runtime.observe(server), { state: "stopping" });
  await runtime.start(server);
  assert.equal(api.deployment().spec.replicas, 0);
  api.pods = [];
  assert.deepEqual(await runtime.observe(server), { state: "stopped" });
  await runtime.start(server);
  assert.equal(api.deployment().spec.replicas, 1);
  assert.deepEqual([...api.resources.keys()], resourcesBefore);
});

test("a deterministic name cannot adopt another world's resource", async () => {
  const api = new API();
  const runtime = new KubernetesRuntime(api, recipe);
  await runtime.create(server);
  api.deployment().metadata.labels!["cloud.example/world-id"] = "another-world";
  await assert.rejects(runtime.create(server), /identity_mismatch/);
  await assert.rejects(runtime.start(server), /identity_mismatch/);
  await assert.rejects(runtime.stop(server), /identity_mismatch/);
});
