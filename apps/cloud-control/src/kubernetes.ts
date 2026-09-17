import { readFileSync } from "node:fs";
import { request } from "node:https";
import { parse } from "yaml";

import type { Runtime, RuntimeObservation, ServerRecord } from "./lifecycle.js";

interface Metadata {
  name: string;
  namespace?: string;
  labels?: Record<string, string>;
  deletionTimestamp?: string;
}
export interface Resource {
  apiVersion: string;
  kind: string;
  metadata: Metadata;
  spec: Record<string, unknown>;
  status?: { conditions?: { type: string; status: string }[] };
}
interface DeploymentSpec extends Record<string, unknown> {
  replicas: number;
  selector: { matchLabels: Record<string, string> };
  template: {
    metadata: { labels: Record<string, string> };
    spec: {
      containers: { ports: { hostIP?: string }[] }[];
      volumes: { name: string; persistentVolumeClaim: { claimName: string } }[];
    };
  };
}
export interface KubernetesAPI {
  call<T>(method: "GET" | "POST" | "PATCH", path: string, body?: unknown): Promise<T>;
}
export class KubernetesError extends Error {
  public constructor(public readonly status: number) { super(`kubernetes_http_${status}`); }
}

export class InClusterAPI implements KubernetesAPI {
  private readonly ca = readFileSync("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt");

  public async call<T>(method: "GET" | "POST" | "PATCH", path: string, body?: unknown): Promise<T> {
    const token = readFileSync("/var/run/secrets/kubernetes.io/serviceaccount/token", "utf8").trim();
    const data = body === undefined ? "" : JSON.stringify(body);
    return new Promise((resolve, reject) => {
      const req = request(new URL(path, "https://kubernetes.default.svc"), {
        method, ca: this.ca,
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": method === "PATCH" ? "application/merge-patch+json" : "application/json",
          "content-length": Buffer.byteLength(data)
        }
      }, response => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk: Buffer) => chunks.push(chunk));
        response.on("error", reject);
        response.on("end", () => {
          if ((response.statusCode ?? 500) >= 400) {
            reject(new KubernetesError(response.statusCode ?? 500));
            return;
          }
          try { resolve(JSON.parse(Buffer.concat(chunks).toString()) as T); }
          catch (error) { reject(error); }
        });
      });
      req.setTimeout(15_000, () => req.destroy(new Error("kubernetes_timeout")));
      req.on("error", reject);
      req.end(data);
    });
  }
}

const namespace = "cloud-minecraft-paper";
const core = `/api/v1/namespaces/${namespace}`;
const deployments = `/apis/apps/v1/namespaces/${namespace}/deployments`;
const serverLabel = "cloud.example/server-id";
const worldLabel = "cloud.example/world-id";

export class KubernetesRuntime implements Runtime {
  public constructor(private readonly api: KubernetesAPI, private readonly recipe: Resource) {}

  public static inCluster(): KubernetesRuntime {
    const recipePath = process.env.CLOUD_PAPER_RECIPE ?? "catalog/games/minecraft-java/paper/k8s/deployment.yaml";
    return new KubernetesRuntime(new InClusterAPI(), parse(readFileSync(recipePath, "utf8")) as Resource);
  }

  private name(server: ServerRecord): string { return `paper-${server.id}`; }

  private async find(path: string, server: ServerRecord): Promise<Resource | null> {
    try {
      const resource = await this.api.call<Resource>("GET", path);
      if (resource.metadata.labels?.[serverLabel] !== server.id ||
          resource.metadata.labels?.[worldLabel] !== server.world_identity) {
        throw new Error("kubernetes_resource_identity_mismatch");
      }
      return resource;
    } catch (error) {
      if (error instanceof KubernetesError && error.status === 404) return null;
      throw error;
    }
  }

  private async ensure(collection: string, resource: Resource, server: ServerRecord): Promise<void> {
    const path = `${collection}/${resource.metadata.name}`;
    if (await this.find(path, server) !== null) return;
    try { await this.api.call("POST", collection, resource); }
    catch (error) {
      if (!(error instanceof KubernetesError && error.status === 409)) throw error;
      if (await this.find(path, server) === null) throw error;
    }
  }

  public async create(server: ServerRecord): Promise<void> {
    const name = this.name(server);
    const labels = { [serverLabel]: server.id, [worldLabel]: server.world_identity };
    await this.ensure(`${core}/persistentvolumeclaims`, {
      apiVersion: "v1", kind: "PersistentVolumeClaim",
      metadata: { name: `${name}-data`, namespace, labels },
      spec: { accessModes: ["ReadWriteOnce"], storageClassName: "local-path-retain",
        resources: { requests: { storage: "10Gi" } } }
    }, server);
    await this.ensure(`${core}/services`, {
      apiVersion: "v1", kind: "Service", metadata: { name, namespace, labels },
      spec: { type: "ClusterIP", selector: labels,
        ports: [{ name: "minecraft", port: 25565, targetPort: "minecraft", protocol: "TCP" }] }
    }, server);
    const deployment = structuredClone(this.recipe);
    deployment.metadata = { name, namespace, labels };
    const spec = deployment.spec as DeploymentSpec;
    spec.replicas = 0;
    spec.selector.matchLabels = labels;
    spec.template.metadata.labels = labels;
    spec.template.spec.volumes.find(volume => volume.name === "data")!.persistentVolumeClaim.claimName = `${name}-data`;
    // The private host port reserves the qualified worker slot during termination.
    spec.template.spec.containers[0]!.ports[0]!.hostIP = "127.0.0.1";
    await this.ensure(deployments, deployment, server);
  }

  public async observe(server: ServerRecord): Promise<RuntimeObservation> {
    const name = this.name(server);
    const [deployment, volume, service, pods] = await Promise.all([
      this.find(`${deployments}/${name}`, server),
      this.find(`${core}/persistentvolumeclaims/${name}-data`, server),
      this.find(`${core}/services/${name}`, server),
      this.api.call<{ items: Resource[] }>("GET",
        `${core}/pods?labelSelector=${encodeURIComponent(`${serverLabel}=${server.id}`)}`)
    ]);
    if (deployment === null) return { state: pods.items.length === 0 ? "absent" : "stopping" };
    if (deployment.spec.replicas === 0) {
      return { state: pods.items.length === 0 ? "stopped" : "stopping" };
    }
    if (server.desired_state === "running" && (volume === null || service === null)) return { state: "absent" };
    const pod = pods.items[0];
    if (pods.items.length === 1 && pod !== undefined && !pod.metadata.deletionTimestamp &&
        pod.status?.conditions?.some(condition => condition.type === "Ready" && condition.status === "True")) {
      return { state: "ready", endpoint: { host: `${name}.${namespace}.svc`, port: 25565 } };
    }
    return { state: "starting" };
  }

  public async start(server: ServerRecord): Promise<void> {
    await this.create(server);
    if ((await this.observe(server)).state !== "stopped") return;
    await this.api.call("PATCH", `${deployments}/${this.name(server)}`, { spec: { replicas: 1 } });
  }

  public async stop(server: ServerRecord): Promise<void> {
    const path = `${deployments}/${this.name(server)}`;
    if (await this.find(path, server) !== null) {
      await this.api.call("PATCH", path, { spec: { replicas: 0 } });
    }
  }
}
