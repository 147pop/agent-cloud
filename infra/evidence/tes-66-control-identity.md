# TES-66 control identity and restart evidence

The live checks ran on `control-1` on 2026-09-12. Both hosts ran K3s
`v1.36.4+k3s1`; PostgreSQL retained the F1 PVC. Paper remained Ready on
`game-1` throughout the control-only deployment and restart.

## Provenance

- Application and PostgreSQL integration checks: commit
  `9fa26126bfc031c43fd8fbbfa7994cc013fbb5f3`, based on `main` at `e8825af`.
- Restart probe: commit `26911bc`, in
  [verify-identity.mjs](../two-host/verify-identity.mjs).
- Application image: `cloud-control:tes-66-9fa2612`, built on the amd64
  control host from a clean Git-bundle clone.
- Observed container image ID:
  `sha256:18e84fbe9ea7cce6750cb3deccae7acc6c86964956aaf7afe8d1b02b5f1d691e`.

## Result

Startup applied migrations `1 minimum_control_plane` and
`2 event_run_ownership`. The second migration prevents an event from referring
to a run belonging to a different server, including a run without a server.
Its PostgreSQL integration test failed before the constraint was added.

The live probe created a uniquely named test server, stopped run, event and
completed idempotency record under the existing operator identity. After a
`cloud-control` rollout restart, a different Pod authenticated as the same
principal and read the same records and stored response. The PostgreSQL PVC
identity did not change. The restart and verification completed in 10 seconds.
The probe removed only its own server and mutation record after verification;
the associated run and event were removed by their foreign-key cascades.

HTTP checks inside the Pod passed before and after restart. A separate check
from the operator's Mac through an encrypted SSH tunnel to the control host
also returned 401 for a missing or invalid token and 200 for the configured
operator token. This verifies the private control path, not a public HTTP route.

## Reproduction

Use the protected operator configuration from the
[two-host guide](../two-host/README.md). Back up the existing PostgreSQL
database before applying migrations. Run the following on `control-1` with
administrative access, from the checked-out repository root:

```sh
docker build -f apps/cloud-control/Dockerfile -t cloud-control:tes-66-9fa2612 .
docker save cloud-control:tes-66-9fa2612 | k3s ctr images import -
k3s kubectl set image deployment/cloud-control -n cloud-system \
  cloud-control=cloud-control:tes-66-9fa2612
k3s kubectl rollout status deployment/cloud-control -n cloud-system --timeout=180s

umask 077
mkdir -p infra/.local/tes-66
pod_before="$(k3s kubectl get pods -n cloud-system -l app=cloud-control -o jsonpath='{.items[0].metadata.uid}')"
pvc_before="$(k3s kubectl get pvc cloud-postgres-data -n cloud-system -o jsonpath='{.metadata.uid}')"
k3s kubectl exec -i -n cloud-system deployment/cloud-control -- \
  node --input-type=module - seed \
  < infra/two-host/verify-identity.mjs > infra/.local/tes-66/identity-before.json

k3s kubectl rollout restart deployment/cloud-control -n cloud-system
k3s kubectl rollout status deployment/cloud-control -n cloud-system --timeout=180s
test "$pod_before" != "$(k3s kubectl get pods -n cloud-system -l app=cloud-control -o jsonpath='{.items[0].metadata.uid}')"
test "$pvc_before" = "$(k3s kubectl get pvc cloud-postgres-data -n cloud-system -o jsonpath='{.metadata.uid}')"
k3s kubectl exec -i -n cloud-system deployment/cloud-control -- \
  node --input-type=module - verify "$(cat infra/.local/tes-66/identity-before.json)" \
  < infra/two-host/verify-identity.mjs
```

The probe reads credentials from the deployed application's environment. Its
snapshot contains fixture identifiers, not credentials. Successful verification
prints `result=passed`, `identity=preserved`, `records=preserved` and
`fixture=removed` as JSON. Run each command with failure checking enabled;
a failed assertion or rollout is not acceptance.

## Supporting checks

- `npm run check`: six tests passed.
- `TEST_DATABASE_URL` set to an isolated local PostgreSQL 17.6 database,
  `npm run test:integration`: four tests passed, including the parent test.
  This checks revocation, ownership constraints, ten concurrent mutation
  claims, conflicting requests and persistence across a new store.
- `bash infra/two-host/test.sh`: passed.
- `python3 benchmarks/minecraft/summarize.py --self-test`: passed.
- Benchmark package and lockfile unchanged; `git diff --check` passed.
- Production Docker build on `control-1`: passed.

This evidence covers TES-66 identity and durable records. Kubernetes
reconciliation, lifecycle endpoints, allocation and the full F4 journey retain
their separate acceptance requirements. Credentials, host addresses, raw
snapshots and the pre-migration backup remain in protected operator storage.
