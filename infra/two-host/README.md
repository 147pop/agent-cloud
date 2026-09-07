# Reproducible two-host installation (TES-151)

This directory packages the installation gate for one `control-1` host and one
`game-1` host. It deploys the minimal `cloud-control` process, PostgreSQL and
the selected Paper recipe. It does not implement token authentication or game
lifecycle operations; those are F2/F3 work. TES-152 will turn this operator
runbook into the contributor-facing clean-clone quickstart.

## Compatible hosts and trust boundary

The verified target is Ubuntu 24.04 with systemd on both machines:

| Role | Architecture | Required capacity and tools | Installed workload |
| --- | --- | --- | --- |
| `control-1` | amd64 | At least 2 CPUs, 2 GiB RAM, 10 GiB free disk, `curl`, Docker Engine and root access | K3s server, PostgreSQL, `cloud-control` |
| `game-1` | arm64 | At least 4 CPUs, 7 GiB RAM, 20 GiB free disk, `curl` and root access | K3s agent, Paper and its world |

The `game-1` minimum combines the selected two-CPU workload with a two-CPU
host reserve, and the 3 GiB total container limit with a 4 GiB memory reserve.
The selected 2 GiB Java heap is inside that 3 GiB container limit. The 10 GiB PVC
storage request is a budget, not an enforced filesystem quota; installation
also requires a 10 GiB free-disk reserve.

Use operator-owned SSH keys and sudo credentials. Keep SSH targets, addresses,
provider configuration, passwords, the K3s join token and raw evidence outside
Git. `game-1` needs only the non-secret deployment values; the PostgreSQL
password and machine token stay on `control-1`.

## Start from a clean clone

Clone the repository into a new directory on each host and check out the same
commit:

```sh
git clone https://github.com/pjcdz/cloud.git cloud
cd cloud
git checkout <verified-commit>
test -z "$(git status --short)"
```

For an unpushed review commit, an operator may transfer a Git bundle over the
same authorized SSH channel and clone that bundle. Do not copy a dirty worktree.

On `control-1`, copy [config.example.env](config.example.env) to the ignored
`infra/.local/tes-151.env`, replace the documentation addresses, choose the
data paths and ports, and generate new operator-owned values for
`POSTGRES_PASSWORD` and `CLOUD_MACHINE_TOKEN`. Protect it with mode `0600`.

On `game-1`, create the same ignored file with the non-secret settings only;
omit `POSTGRES_PASSWORD` and `CLOUD_MACHINE_TOKEN`. `prepare-host.sh` and
`reset-host.sh` deliberately use the public configuration mode there.

Minecraft starts only after the operator has read and accepted the
[Minecraft EULA](https://aka.ms/MinecraftEULA) and changed this exact setting:

```sh
MINECRAFT_EULA=TRUE
```

The scripts refuse every other value.

## Optional dedicated-host reset

`reset-host.sh` is destructive and is not part of an ordinary reapply. Use it
only on dedicated hosts after inspecting the selected paths. The control reset
refuses to proceed if it finds a non-system workload outside `cloud-system` or
`cloud-minecraft-paper`.

Run the game reset first, then control:

```sh
sudo infra/two-host/reset-host.sh game infra/.local/tes-151.env
sudo infra/two-host/reset-host.sh control infra/.local/tes-151.env
```

The scripts invoke the official K3s uninstallers and clear contents only below
the validated `/var/lib/cloud/...` data path for the selected role. They do not
change provider firewall rules or unrelated directories.

## Install the pinned cluster

Load the local values without printing them. On `control-1`, install the pinned
K3s server and apply its firewall rules:

```sh
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$CONTROL_NODE_NAME" \
  CONTROL_PRIVATE_ADDRESS="$CONTROL_PRIVATE_ADDRESS" \
  infra/k3s/install-control.sh
sudo infra/k3s/firewall-control.sh \
  "$GAME_PRIVATE_ADDRESS" "$CONTROL_API_CLIENT_CIDR" "$CONTROL_API_PORT"
```

Read `/var/lib/rancher/k3s/server/node-token` through the authorized channel
without capturing it in logs. On `game-1`, pass that value directly to the
agent installer and apply the game firewall:

```sh
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$GAME_NODE_NAME" \
  GAME_PRIVATE_ADDRESS="$GAME_PRIVATE_ADDRESS" \
  K3S_URL="https://$CONTROL_PRIVATE_ADDRESS:6443" \
  K3S_TOKEN='<join-token-from-control-1>' \
  infra/k3s/install-game.sh
sudo infra/k3s/firewall-game.sh "$CONTROL_PRIVATE_ADDRESS" "$GAME_PORT"
sudo infra/two-host/prepare-host.sh game infra/.local/tes-151.env
```

The placeholder above is an instruction, not a value to store in a file or
shell history. The operator should use a protected prompt or equivalent
out-of-band mechanism.

## Deploy and verify

Back on `control-1`, prepare PostgreSQL storage, build and import the pinned
`cloud-control` image, create the Kubernetes Secret and apply all resources:

```sh
sudo infra/two-host/prepare-host.sh control infra/.local/tes-151.env
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
```

The verifier requires two Ready nodes, correct taint/labels and placement,
bound retained volumes, a ClusterIP-only PostgreSQL service, non-admin service
accounts, the configured machine-token input, process readiness, configured
resource limits, the control health endpoint and the direct worker-address TCP
path to Minecraft. From the operator machine, separately verify the actual
direct path and that PostgreSQL and K3s administration are not reachable:

```sh
nc -vz "$GAME_DIRECT_ADDRESS" "$GAME_PORT"
curl --fail "http://<control-address>:$CONTROL_API_PORT/healthz"
! nc -vz -w 3 '<control-address>' 5432
! nc -vz -w 3 '<control-address>' 6443
```

Keep the exact addresses and output in `infra/.local/`, not in committed
evidence.

## Persistence reapply gate

After the first pass, create a PostgreSQL probe row and a marker in the stopped
Paper data path. Record their identifiers and hashes privately. Then run the
same non-destructive preparation, K3s installers, firewall commands and
`deploy.sh` a second time. Do not run `reset-host.sh` on the second pass.

```sh
sudo infra/two-host/prepare-host.sh control infra/.local/tes-151.env
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
```

The second pass must preserve both PV/PVC bindings and both probes while all
three workloads return to Ready. Reapplying a PVC request does not delete its
volume, and the renderer never places credentials in a manifest.

## Troubleshooting

- If the agent cannot join, verify the current addresses, provider allowlists,
  the `6443/tcp` and `51820/udp` rules and the out-of-band join token.
- If a local PV remains Pending, confirm the configured node name exactly
  matches `kubectl get nodes` and the selected data path exists with the owner
  reported by `prepare-host.sh`.
- If Paper is Pending, confirm `MINECRAFT_EULA=TRUE`, the game label, available
  CPU/memory and at least the configured storage budget plus disk reserve.
- If `cloud-control` is `ErrImageNeverPull`, rerun `deploy.sh` as root on
  `control-1`; it builds with Docker and imports into K3s containerd.
- If PostgreSQL is not Ready, inspect the pod events and the prepared path
  ownership without printing the Secret.

See the lower-level [K3s installer](../k3s/README.md), the
[infrastructure boundary](../README.md) and the [repository overview](../../README.md).
