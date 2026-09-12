# TES-62 Minecraft protocol readiness evidence

The two-host K3s deployment was tested on 2026-09-10 at commit
`fc46409fa3d343ae4a2b66d43b028eea0d044e64`.

## Result

The Paper replacement Pod remained outside Service endpoints until the bundled
`mc-monitor` completed a Minecraft status request. The cold rollout completed
without restarting the container.

The deployed probes were:

| Probe | Command | Period | Timeout | Failure threshold |
| --- | --- | --- | --- | --- |
| Startup | `mc-monitor status --host 127.0.0.1 --port 25565` | 10 seconds | 5 seconds | 60 |
| Readiness | `mc-monitor status --host 127.0.0.1 --port 25565` | 10 seconds | 5 seconds | 3 |

## Observed transition

A temporary ClusterIP Service selected the Paper Deployment during a Recreate
rollout. A private trace sampled Pod readiness, restart count, ready endpoint
count and the result of the same `mc-monitor` command. The replacement Pod had
22 observations:

| Pod Ready | Ready endpoints | Protocol result | Observations |
| --- | --- | --- | --- |
| False | 0 | Fail | 7 |
| False | 0 | Pass | 2 |
| True | 1 | Pass | 13 |

There were no replacement-Pod observations where Ready was true before a
successful protocol response, and no endpoint appeared while the protocol
check failed. The maximum restart count was zero. During termination, the old
Pod had one stale Ready observation after its protocol check failed, but the
Service had already removed its endpoint.

The temporary Service was deleted after the trace and was not added to the
repository manifests. Deterministic workload Services remain part of TES-69.

## Commands and checks

The following commands completed successfully on `control-1` using the
protected operator configuration:

```sh
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
```

The verifier confirmed both nodes Ready, expected workload placement, retained
PVCs, resource limits, host reserve, local control health, Minecraft protocol
readiness through `mc-monitor`, and the direct game TCP path.

Credentials, host addresses, Pod names and the raw operational trace remain in
ignored private storage and are intentionally excluded from Git.
