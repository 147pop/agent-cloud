# TES-64: scoped control service account

On 2026-09-12 UTC, the probe running inside the live `cloud-control` Pod used
its projected service-account credential to stop Paper, wait until its old
Pod disappeared, and start a Ready replacement. It also passed three creation
dry-runs and received `403 Forbidden` for all six forbidden operations.

## Verified inputs

- RBAC and probe source: `85bf3ea`, a clean Git bundle clone on `control-1`.
- K3s on both hosts: `v1.36.4+k3s1`.
- Existing control image: `cloud-control:tes-66-9fa2612`; only its Pod token
  mounting setting and the four new RBAC objects changed for this task.
- Existing Paper: version `26.2`, build `121`, pinned image
  `itzg/minecraft-server@sha256:efa878ddb49cf5251b2e5f2ad71b08fd2f7236c1f7907433f6697258b31d2ce4`.
- Workload namespace: the installation's existing `cloud-minecraft-paper`.
  No namespace, world or PVC was created or deleted by the probe.

## Reproduction

Deploy the repository manifests, then follow the service-account verification
section in [the two-host guide](../two-host/README.md#verify-the-control-service-account).
The guide checks zero connected players and the absence of a mounted token
inside Paper before running the probe from the repository root on `control-1`:

```sh
sudo k3s kubectl exec -i -n cloud-system deployment/cloud-control -- \
  node --input-type=module < infra/two-host/verify-rbac.mjs
```

Observed result:

```json
{
  "result": "passed",
  "credentials": "projected-service-account",
  "namespace": "cloud-minecraft-paper",
  "create_dry_runs": 3,
  "forbidden_requests": 6,
  "lifecycle": "stop-and-start-ready"
}
```

Node and workload reads succeeded. Kubernetes accepted server dry-runs for a
Deployment, Service and PVC, and a metadata patch to the existing PVC. Secret
reads in both game and control namespaces, modification of the control
Deployment, node modification, cluster-role creation and retained-PVC deletion
all returned `403`. Every negative write used server dry-run as an additional
guard against an unexpected permission grant.

The caller machine token and projected Kubernetes token were compared inside
the Pod and were distinct; neither was printed. The Paper container had no
mounted Kubernetes token before or after replacement. After the lifecycle
check, `mc-monitor status` reported Paper `26.2`, zero connected players and
a two-player limit.

## Verification boundary

`bash infra/two-host/test.sh`, `node --check infra/two-host/verify-rbac.mjs`
and `git diff --check` passed. Initial probe attempts exposed malformed HTTP
request framing in the verification client before the lifecycle check. The
corrected source sets the payload length and omits GET bodies; the complete
live run above passed with that source.

This verifies Kubernetes permissions and stop/start access from the control
Pod. Creation used API server dry-run and did not provision another world.
Durable product lifecycle operations and full real-resource creation remain
TES-69 and F3/F4 acceptance work.
