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

With `CLOUD_RUNTIME=kubernetes`, the process reconciles every second through
its projected service-account token and cluster CA. It loads the pinned Paper
recipe from `catalog/games/minecraft-java/paper/k8s/deployment.yaml`; the image
includes that file. `CLOUD_PAPER_RECIPE` can override its path for development.
The installer applies the retained local-path StorageClass. Each logical
server has its own deterministic Deployment, PVC and Service. Create retries
preserve existing resources and replicas. Stop retains both the PVC and Service;
start waits until all old Pods are gone. The private host port also reserves
the single qualified worker slot during termination.

Readiness comes from the recipe's Minecraft protocol probe. TES-69 returns an
internal Service address; TES-77 supplies the stable external endpoint. The
process exposes health and machine identity; F3 connects REST, MCP and CLI to
the same mutation contract. PostgreSQL tests use a controllable fake runtime;
live Kubernetes acceptance has a separate operator probe.

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
TES-71 campaign starts a separate Node process running the production store
and reconciler, with a fake runtime served over IPC. It sends `SIGKILL` before
and after observation and each create/start/stop effect: twelve crash cases.
For an after-effect crash, the fake resource changes before the child receives
an acknowledgement. Fresh processes then recover against the same PostgreSQL
records and runtime resources.

Every case checks the final desired state, stable world identity, unchanged
response replay, a traceable request ID and at most one active run. The fake
runtime rejects a repeated effect. This proves process recovery for the
shared contract; Kubernetes restart and partial-resource recovery still need
the TES-69 and F4 runs.
