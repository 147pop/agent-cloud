# TES-151 two-host installation evidence

This record covers the reproducible two-host deployment at commit
`6e10e24f28bf8beafe2a2d02d2955b5f63bdd70d`.

## Environment

- Ubuntu 24.04 hosts: amd64 control node and arm64 game node.
- K3s: `v1.36.4+k3s1`.
- The control node is tainted `cloud.example/role=control:NoSchedule` and
  labeled `cloud.example/role=control`; the game node is labeled
  `cloud.example/role=game`.
- The game workload is configured for 2 CPU, a 2 GiB Java heap, 3 GiB memory,
  and a 10 GiB PVC. Host reserves are 2 CPU, 4 GiB memory, and 10 GiB disk.

## Verification

The first installation pass completed the control and game setup, applied the
manifests, and passed `infra/two-host/verify.sh`. The provider firewall rules
were then updated to permit the public game TCP port. A non-blocking TCP probe
from the operator and a second probe from control-1 both succeeded. The
verifier confirmed Ready nodes, workload placement, ClusterIP-only PostgreSQL,
the machine-token input without printing its value, the game node's local
interface address, and the configured game TCP path.

The second pass ran `infra/two-host/deploy.sh` without resetting either host.
Both rollouts completed and the verifier passed again. A PostgreSQL probe row
remained present (`1` matching row), the Paper data PVC identity was unchanged,
the PostgreSQL data PVC identity was unchanged, and a marker written to the
game data volume retained the same hash before and after the second pass.

The control-local API health check passed as part of verification. An HTTP
probe to the control public address from the operator was filtered by the
provider web-security layer; this is external filtering, not an application
health failure, and no public health claim is based on that probe.

## Reproduction commands

```text
bash infra/two-host/test.sh
for script in infra/k3s/*.sh infra/two-host/*.sh; do bash -n "$script"; done
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
```

All credentials, host addresses, SSH targets, provider-rule details, and raw
operational logs remain in ignored local files and are intentionally excluded
from this evidence and from Git.
