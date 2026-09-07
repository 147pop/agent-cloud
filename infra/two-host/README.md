# Two-host contributor quickstart (TES-146 / TES-152)

This guide takes a contributor from a clean checkout to the F1 installation
gate: one `control-1` host running the K3s server, PostgreSQL and
`cloud-control`, and one `game-1` host running the K3s agent, the pinned Paper
recipe and its persistent world. It covers host preparation, private cluster
connectivity, deployment, readiness and a non-destructive reapply.

It does not implement token authentication, control-plane lifecycle
operations or the complete playable journey. Those are F2/F3 work and are
accepted separately by [TES-148](https://linear.app/workspace/issue/TES-148/l4-accept-the-clean-clone-local-journey).
This guide also does not configure public account onboarding, Cloudflare or
any other managed-service integration.

## Host contract and trust boundary

The verified target is Ubuntu 24.04 with systemd on both machines:

Both hosts also need Git and a POSIX shell. The examples use OpenSSL to
generate local operator values and persistence markers.

| Role | Architecture | Minimum capacity and required commands | Installed workload |
| --- | --- | --- | --- |
| `control-1` | amd64 | 2 CPUs, 2 GiB RAM, 10 GiB free disk, `curl`, Docker Engine, `ufw` and root access | K3s server, PostgreSQL, `cloud-control` |
| `game-1` | arm64 | 4 CPUs, 7 GiB RAM, 20 GiB free disk, `curl`, `ufw` and root access | K3s agent, Paper and its world |

The `game-1` minimum is the selected two-CPU workload plus a two-CPU host
reserve, and the 3 GiB total container memory limit plus a 4 GiB host memory
reserve. The selected 2 GiB Java heap fits inside the 3 GiB container limit.
The 10 GiB PVC/storage request is a budget, not an enforced filesystem quota;
installation also requires the 10 GiB free-disk reserve.

Use operator-owned SSH keys and sudo credentials. Keep SSH targets, addresses,
provider configuration, passwords, the K3s join token and raw evidence outside
Git. `game-1` needs only non-secret deployment values: the PostgreSQL password
and machine token stay on `control-1`.

Keep the three game address roles distinct:

- `GAME_NODE_ADDRESS` is assigned to a local `game-1` interface and becomes
  the Kubernetes `InternalIP`.
- `GAME_CLUSTER_SOURCE_ADDRESS` is the routable or NAT source address that
  `control-1` sees and allows through its firewall.
- `GAME_DIRECT_ADDRESS` is the player-facing Minecraft endpoint. The last two
  may coincide, but neither may be forced as a node IP unless it is actually
  assigned to the host.

## 1. Start from the same clean clone on both hosts

Run the following on both `control-1` and `game-1`. Use the same verified
commit on both hosts; do not mix a local checkout with a different branch or
commit.

```sh
git clone https://github.com/pjcdz/cloud.git cloud
cd cloud
git checkout <verified-commit>
test -z "$(git status --short)"
```

For an unpushed review commit, transfer a Git bundle over the same authorized
SSH channel and clone that bundle. The checkout must still be clean before any
installation command runs.

## 2. Create protected local configuration

`infra/.local/` is ignored by Git. The example file contains documentation
values only; replace every host-specific address, path, port and placeholder
with values for the installation. Keep the pinned K3s version and resource
settings unless the installation has an explicitly reviewed reason to change
them.

On `control-1`, create the full configuration and edit it in a protected
editor:

```sh
cd cloud
mkdir -p infra/.local
cp infra/two-host/config.example.env infra/.local/tes-151.env
chmod 600 infra/.local/tes-151.env
vi infra/.local/tes-151.env
```

Set `MINECRAFT_EULA=TRUE` only after reading and accepting the
[Minecraft EULA](https://aka.ms/MinecraftEULA). Generate two different
operator-owned values, each at least 20 bytes, and put them only in the
control host file:

```sh
openssl rand -hex 32
openssl rand -hex 32
```

Use the first output for `POSTGRES_PASSWORD` and the second for
`CLOUD_MACHINE_TOKEN`. Do not paste either value into Git, an issue, a pull
request, a captured log or shell history. Keep the file mode at `0600`:

```sh
chmod 600 infra/.local/tes-151.env
test "$(stat -c '%a' infra/.local/tes-151.env)" = 600
```

On `game-1`, create a separate local copy with the same non-secret values and
remove both secret fields. Use the same relative path so the public-mode host
scripts can load it:

```sh
cd cloud
mkdir -p infra/.local
cp infra/two-host/config.example.env infra/.local/tes-151.env
sed -i '/^POSTGRES_PASSWORD=/d; /^CLOUD_MACHINE_TOKEN=/d' infra/.local/tes-151.env
chmod 600 infra/.local/tes-151.env
vi infra/.local/tes-151.env
```

The game file must have `MINECRAFT_EULA=TRUE`, the three correctly assigned
game address roles and no `POSTGRES_PASSWORD` or `CLOUD_MACHINE_TOKEN` lines.
The deployment script creates the Kubernetes Secret only on `control-1` from
the protected full configuration.

## 3. Install and prepare `control-1`

Run every command in this section on `control-1` from the repository root.
Never enable shell tracing while the local configuration is loaded.

### 3.1 Install the pinned K3s server

Load only the values needed by the installer into the command environment and
run the repository's pinned installer:

```sh
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$CONTROL_NODE_NAME" \
  CONTROL_PRIVATE_ADDRESS="$CONTROL_PRIVATE_ADDRESS" \
  infra/k3s/install-control.sh
```

The installer uses the exact `K3S_VERSION` from the configuration, enables
K3s's `wireguard-native` backend, disables bundled Traefik and ServiceLB, and
taints/labels the control node so game workloads cannot land there. It records
the join-token path without printing the token.

### 3.2 Prepare the control host

Run the control preparation after the K3s server is installed. It verifies the
required `k3s` and Docker commands and creates the PostgreSQL path below the
validated `/var/lib/cloud/` boundary with the required owner and mode:

```sh
sudo infra/two-host/prepare-host.sh control infra/.local/tes-151.env
```

### 3.3 Apply the control firewall

The repository firewall uses `ufw` and leaves existing SSH rules untouched. It
allows the game source address to reach the K3s API and WireGuard tunnel, and
allows only the configured client CIDR to reach the control API port:

```sh
set -a
. infra/.local/tes-151.env
set +a
sudo infra/k3s/firewall-control.sh \
  "$GAME_CLUSTER_SOURCE_ADDRESS" \
  "$CONTROL_API_CLIENT_CIDR" \
  "$CONTROL_API_PORT"
```

Any provider-level rule required for the two hosts' private path is an
operator task outside this repository. Do not put provider identifiers or
private rule output in Git.

## 4. Transfer the join token and install `game-1`

The token transfer is out of band. On `control-1`, display it only in a
protected operator terminal and transfer it through an authorized protected
channel; do not save it in a repository file, command history or log:

```sh
sudo cat /var/lib/rancher/k3s/server/node-token
```

Run the next commands on `game-1`. Enter the token at the hidden prompt when
asked; the shell variable is cleared immediately after installation:

```sh
cd cloud
set -a
. infra/.local/tes-151.env
set +a
read -r -s K3S_TOKEN
printf '\n'
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$GAME_NODE_NAME" \
  GAME_NODE_ADDRESS="$GAME_NODE_ADDRESS" \
  K3S_URL="https://$CONTROL_PRIVATE_ADDRESS:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  infra/k3s/install-game.sh
unset K3S_TOKEN
```

The agent installer sets `GAME_NODE_ADDRESS` as the node IP and applies the
`cloud.example/role=game` label. The control address used in `K3S_URL` must be
the private address reachable from `game-1`, not a NAT or player-facing value.

### 4.1 Apply the game firewall

Still on `game-1`, allow the WireGuard tunnel from `control-1` and the direct
Minecraft TCP port:

```sh
set -a
. infra/.local/tes-151.env
set +a
sudo infra/k3s/firewall-game.sh "$CONTROL_PRIVATE_ADDRESS" "$GAME_PORT"
```

### 4.2 Prepare the game host

The game preparation creates the Minecraft data path with the expected owner
and checks workload capacity plus the configured host reserve:

```sh
sudo infra/two-host/prepare-host.sh game infra/.local/tes-151.env
```

It checks `GAME_CPU + GAME_HOST_RESERVED_CPU`,
`GAME_MEMORY + GAME_HOST_RESERVED_MEMORY_GIB`, and
`GAME_STORAGE_GIB + GAME_HOST_RESERVED_DISK_GIB`. The storage value remains a
PVC allocation budget; it does not create a filesystem quota.

## 5. Deploy from `control-1` and verify installation readiness

Run these commands on `control-1`. `deploy.sh` loads the full protected
configuration, creates a temporary Secret input with restrictive permissions,
builds and imports the pinned local `cloud-control` image, and applies the
control, storage and Paper resources:

```sh
cd cloud
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
```

`verify.sh` proves, without printing secret values:

- both nodes are Ready, the control taint and game label are present, and the
  workloads are placed on their intended host roles;
- the game node's Kubernetes `InternalIP` equals `GAME_NODE_ADDRESS`;
- PostgreSQL is `ClusterIP`-only, has no node port and is not listening on the
  control host's port 5432;
- the control and PostgreSQL service accounts do not have cluster-wide admin
  access;
- the machine-token input is present and PostgreSQL accepts a readiness probe;
- both PVCs are Bound and their PVs use `Retain`;
- Paper's configured CPU, memory and host port match the configuration and the
  game node still satisfies the CPU reserve;
- the control health endpoint works locally and the configured direct game TCP
  path works from `control-1`.

From the authorized operator network, separately check the direct game path
and the private administration boundary. Replace the angle-bracket values with
the control host address only in your private terminal:

```sh
set -a
. infra/.local/tes-151.env
set +a
nc -vz "$GAME_DIRECT_ADDRESS" "$GAME_PORT"
curl --fail "http://<control-address>:$CONTROL_API_PORT/healthz"
! nc -vz -w 3 '<control-address>' 5432
! nc -vz -w 3 '<control-address>' 6443
```

The first probe is the direct player-facing game path. PostgreSQL and K3s
administration remain private; use the control host's authorized local access
for cluster administration. These checks establish installation readiness,
not F2/F3 API behavior or TES-148's complete playable journey.

## 6. Reapply without deleting durable data

Do not use `reset-host.sh` for this gate. It is a destructive dedicated-host
reset that invokes K3s uninstallers and clears only selected data paths; it is
not part of an ordinary reapply.

After the first successful pass, record private probes in an ignored local
directory. Record identifiers and hashes rather than raw private logs.

On `control-1`, record the PVC/PV identities and the result of the same
operator-defined PostgreSQL probe query before and after reapply:

```sh
mkdir -p infra/.local/tes-151-persistence/before
for claim in cloud-system/cloud-postgres-data cloud-minecraft-paper/paper-e0-oracle-data; do
  namespace="${claim%/*}"
  name="${claim#*/}"
  sudo k3s kubectl get pvc "$name" -n "$namespace" -o jsonpath='{.metadata.uid}{"\n"}' \
    > "infra/.local/tes-151-persistence/before/${namespace}-${name}.pvc.uid"
done
for volume in cloud-postgres-data cloud-paper-data; do
  sudo k3s kubectl get pv "$volume" -o jsonpath='{.metadata.uid}{"\n"}' \
    > "infra/.local/tes-151-persistence/before/${volume}.pv.uid"
done

# Set this only in the protected local shell to identify the row created by
# your private probe; use the same query and output shape after reapply.
read -r POSTGRES_PROBE_QUERY
sudo k3s kubectl exec -n cloud-system statefulset/cloud-postgres -- \
  psql -U cloud -d cloud -Atc "$POSTGRES_PROBE_QUERY" \
  > infra/.local/tes-151-persistence/before/postgres-probe.txt
unset POSTGRES_PROBE_QUERY
```

On `game-1`, stop the Paper workload through the installation operator path,
write a unique marker below `GAME_DATA_PATH`, and retain only its hash:

```sh
mkdir -p infra/.local/tes-151-persistence/before
set -a
. infra/.local/tes-151.env
set +a
MARKER_PATH="$GAME_DATA_PATH/.tes-151-reapply-marker"
printf '%s\n' "$(openssl rand -hex 16)" | sudo tee "$MARKER_PATH" >/dev/null
sudo sha256sum "$MARKER_PATH" \
  > infra/.local/tes-151-persistence/before/world-marker.sha256
```

Repeat the non-destructive installation sequence in the same order. Run the
control commands on `control-1`; run the game commands on `game-1`. Use the
same verified commit and configuration values. Transfer the current join
token through the protected prompt again; never put it in the commands below
or in a file.

On `control-1`:

```sh
cd cloud
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$CONTROL_NODE_NAME" \
  CONTROL_PRIVATE_ADDRESS="$CONTROL_PRIVATE_ADDRESS" \
  infra/k3s/install-control.sh
sudo infra/k3s/firewall-control.sh \
  "$GAME_CLUSTER_SOURCE_ADDRESS" \
  "$CONTROL_API_CLIENT_CIDR" \
  "$CONTROL_API_PORT"
sudo infra/two-host/prepare-host.sh control infra/.local/tes-151.env
```

On `game-1`:

```sh
cd cloud
set -a
. infra/.local/tes-151.env
set +a
read -r -s K3S_TOKEN
printf '\n'
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$GAME_NODE_NAME" \
  GAME_NODE_ADDRESS="$GAME_NODE_ADDRESS" \
  K3S_URL="https://$CONTROL_PRIVATE_ADDRESS:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  infra/k3s/install-game.sh
unset K3S_TOKEN
sudo infra/k3s/firewall-game.sh "$CONTROL_PRIVATE_ADDRESS" "$GAME_PORT"
sudo infra/two-host/prepare-host.sh game infra/.local/tes-151.env
```

Finish on `control-1`:

```sh
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
```

Record the same PVC/PV UIDs, PostgreSQL probe output and world marker hash in
`infra/.local/tes-151-persistence/after/`, then compare the private records:

```sh
diff -ru infra/.local/tes-151-persistence/before/ \
  infra/.local/tes-151-persistence/after/
```

The reapply gate passes only when the PVC/PV identities are unchanged, the
PostgreSQL probe row still exists, the world marker hash is unchanged, and
the PostgreSQL, `cloud-control` and Paper workloads return to Ready. A second
`deploy.sh` applies resources and restarts the stateless control process; it
does not delete durable PVCs or host data paths.

The [TES-151 live installation evidence](../evidence/tes-151-two-host-installation.md)
records an existing two-host result with the same persistence checks. It is a
reference for the installation gate, not a place to copy private addresses,
credentials, provider identifiers or raw logs.

## Troubleshooting

- If the agent cannot join, verify that `GAME_NODE_ADDRESS` exists on a local
  interface, `GAME_CLUSTER_SOURCE_ADDRESS` matches the source seen by
  `control-1`, the current provider allowlists permit `6443/tcp` and
  `51820/udp`, and the out-of-band join token is current.
- If a local PV remains Pending, confirm that the configured node name exactly
  matches `kubectl get nodes` and that the selected data path exists with the
  owner reported by `prepare-host.sh`.
- If Paper is Pending, confirm `MINECRAFT_EULA=TRUE`, the game label,
  available CPU/memory, and at least the configured storage budget plus disk
  reserve.
- If `cloud-control` is `ErrImageNeverPull`, rerun `deploy.sh` as root on
  `control-1`; it builds with Docker and imports the image into K3s containerd.
- If PostgreSQL is not Ready, inspect pod events and prepared-path ownership
  without printing the Kubernetes Secret or its values.

For lower-level details, see the [K3s installer guide](../k3s/README.md), the
[infrastructure boundary](../README.md), the [repository overview](../../README.md)
and the [example configuration](config.example.env). Those documents retain
the same rule: documentation values are examples, while private operational
values stay outside Git.
