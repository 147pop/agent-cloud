import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { request } from 'node:https';
import { setTimeout as delay } from 'node:timers/promises';

const credentials = '/var/run/secrets/kubernetes.io/serviceaccount';
const token = readFileSync(`${credentials}/token`, 'utf8').trim();
const ca = readFileSync(`${credentials}/ca.crt`);
assert.ok(token !== process.env.CLOUD_MACHINE_TOKEN, 'Kubernetes and caller credentials must differ');
assert.equal(readFileSync(`${credentials}/namespace`, 'utf8'), 'cloud-system');
const namespace = 'cloud-minecraft-paper';
const core = `/api/v1/namespaces/${namespace}`;
const apps = `/apis/apps/v1/namespaces/${namespace}/deployments`;
const workload = `${apps}/paper-e0-oracle`;
const selector = 'labelSelector=app%3Dpaper-e0-oracle';

async function api(method, path, body, expected = 200) {
  const result = await new Promise((resolve, reject) => {
    const req = request(`https://kubernetes.default.svc${path}`, {
      method, ca, headers: {
        authorization: `Bearer ${token}`,
        'content-type': method === 'PATCH' ? 'application/merge-patch+json' : 'application/json',
      }, timeout: 10000,
    }, res => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('Kubernetes request timed out')));
    req.end(body === undefined || method === 'GET' ? undefined : JSON.stringify(body));
  });
  assert.equal(result.status, expected, `${method} ${path}`);
  return JSON.parse(result.body);
}

async function waitForPods(check) {
  const deadline = Date.now() + 600000;
  while (Date.now() < deadline) {
    const { items } = await api('GET', `${core}/pods?${selector}`);
    if (check(items)) return items;
    await delay(1000);
  }
  throw new Error('Paper did not reach the expected Pod state within 600 seconds');
}

await api('GET', '/api/v1/nodes');
for (const path of [apps, `${core}/pods`, `${core}/services`, `${core}/persistentvolumeclaims`]) {
  await api('GET', path);
}

const deployment = await api('GET', workload);
assert.equal(deployment.spec.replicas, 1);
const original = await api('GET', `${core}/pods?${selector}`);
assert.equal(original.items.length, 1);
const originalUid = original.items[0].metadata.uid;

const fixture = `tes-64-${Date.now()}`;
await api('POST', `${apps}?dryRun=All`, {
  apiVersion: 'apps/v1', kind: 'Deployment', metadata: { name: fixture },
  spec: { ...deployment.spec, replicas: 0 },
}, 201);
await api('POST', `${core}/services?dryRun=All`, {
  apiVersion: 'v1', kind: 'Service', metadata: { name: fixture },
  spec: { selector: { app: fixture }, ports: [{ port: 25565 }] },
}, 201);
await api('POST', `${core}/persistentvolumeclaims?dryRun=All`, {
  apiVersion: 'v1', kind: 'PersistentVolumeClaim', metadata: { name: fixture },
  spec: { accessModes: ['ReadWriteOnce'], storageClassName: 'cloud-local-static',
    resources: { requests: { storage: '10Gi' } } },
}, 201);
await api('PATCH', `${core}/persistentvolumeclaims/paper-e0-oracle-data?dryRun=All`, {
  metadata: { annotations: { 'cloud.example/tes-64': fixture } },
});

for (const [method, path] of [
  ['GET', `${core}/secrets`],
  ['GET', '/api/v1/namespaces/cloud-system/secrets'],
  ['PATCH', '/apis/apps/v1/namespaces/cloud-system/deployments/cloud-control?dryRun=All'],
  ['PATCH', '/api/v1/nodes/game-1?dryRun=All'],
  ['POST', '/apis/rbac.authorization.k8s.io/v1/clusterroles?dryRun=All'],
  ['DELETE', `${core}/persistentvolumeclaims/paper-e0-oracle-data?dryRun=All`],
]) {
  await api(method, path, {}, 403);
}

try {
  await api('PATCH', workload, { spec: { replicas: 0 } });
  await waitForPods(items => items.length === 0);
} finally {
  await api('PATCH', workload, { spec: { replicas: 1 } });
}
await waitForPods(items => items.length === 1 && items[0].metadata.uid !== originalUid &&
  items[0].status.conditions?.some(condition => condition.type === 'Ready' && condition.status === 'True'));

console.log(JSON.stringify({ result: 'passed', credentials: 'projected-service-account',
  namespace, create_dry_runs: 3, forbidden_requests: 6, lifecycle: 'stop-and-start-ready' }));
