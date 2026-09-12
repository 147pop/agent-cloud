# Cloud control

`ControlStore.mutate` is the shared durable lifecycle entry point for create,
start and stop. It commits the caller's mutation key, response, logical server,
desired state, active run and event in one PostgreSQL transaction. Repeating
the same key and body returns the original response. Ownership is checked for
existing servers; a changed operation or body raises a 409 `ControlError`.

`Reconciler.reconcile` observes the runtime before applying one missing effect.
The runtime receives the stable logical server and world identities. Its
create, start and stop operations must be idempotent under those identities.
The reconciler waits while startup or termination is already in progress.
It marks a run stopped only after observing an absent or stopped workload.

A PostgreSQL session advisory lock serializes reconciliation for one server.
No database transaction spans a runtime call. Observation writes check the
desired-state generation so an older observation cannot replace newer intent.
`tick` visits managed servers, including converged ones so runtime drift can
be observed, and reports failures after allowing other servers to progress.

The process currently exposes health and machine identity. TES-69 connects
this lifecycle contract to real Kubernetes operations; F3 connects the same
mutation contract to REST, MCP and CLI. The focused tests use real PostgreSQL
with a controllable fake runtime; they do not establish K3s acceptance.

From the repository root:

```sh
npm ci
npm run check
TEST_DATABASE_URL='<disposable PostgreSQL connection URL>' npm run test:integration
```

The integration tests create and remove isolated schemas. They cover delayed
termination, world identity across restart, an effect completed before a
control restart, intent changed during a start, stale readiness and progress
past an individual runtime failure. TES-70 also sends twenty concurrent copies
of each create/stop/start mutation through two database pools and races ten
reconciliations at each stage. It verifies one effect per operation, one active
run, durable response replay and a 409 control error for a changed body or
operation. HTTP transport and real K3s repetitions remain F3/F4 checks. The
complete crash-point campaign belongs to TES-71.
