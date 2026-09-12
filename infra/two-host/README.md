# Two-host contributor quickstart (TES-146 / TES-152)

This guide takes a contributor from a clean checkout to the F1 installation
gate: one `control-1` host running the K3s server, PostgreSQL and
`cloud-control`, and one `game-1` host running the K3s agent, the pinned Paper
recipe and its persistent world. It covers host preparation, private cluster
connectivity, deployment, readiness and a non-destructive reapply.

It does not implement token authentication, control-plane lifecycle
operations or the complete playable journey. Those are F2/F3 work and are
accepted separately by [TES-148](https://linear.app/workspace/issue/TES-148/f4-accept-the-reproducible-two-host-minecraft-foundation).
This guide also does not configure public account onboarding, Cloudflare or
any other managed-service integration.

## Host contract and trust boundary

The verified target is Ubuntu 24.04 with systemd on both machines:

Both hosts also need Git, Bash and the `netcat-openbsd` package (`nc`) for
the documented network probes; all commands in this guide are intended to run
from Bash, not only from a generic POSIX shell. The examples use OpenSSL to
generate local operator values and persistence markers. The operator machine
used for direct/private probes also needs `curl` and `netcat-openbsd` (`nc`).

| Role | Architecture | Minimum capacity and required commands | Installed workload |
| --- | --- | --- | --- |
| `control-1` | amd64 | 2 CPUs, 2 GiB RAM, 10 GiB free disk, `curl`, Docker Engine, `ufw`, `netcat-openbsd` (`nc`) and root access | K3s server, PostgreSQL, `cloud-control` |
| `game-1` | arm64 | 4 CPUs, 7 GiB RAM, 20 GiB free disk, `curl`, `ufw`, `netcat-openbsd` (`nc`) and root access | K3s agent, Paper and its world |

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

```bash
git clone https://github.com/pjcdz/cloud.git cloud
cd cloud
read -r -p 'Verified commit or ref: ' VERIFIED_COMMIT
if [[ -z "$VERIFIED_COMMIT" || "$VERIFIED_COMMIT" == -* ||
  "$VERIFIED_COMMIT" == *[!A-Za-z0-9._/-]* ||
  "$VERIFIED_COMMIT" == *..* || "$VERIFIED_COMMIT" == *"@{"* ]]; then
  echo 'VERIFIED_COMMIT must be a safe SHA or ref name' >&2
  exit 1
fi
if ! git rev-parse --verify --quiet "$VERIFIED_COMMIT^{commit}" >/dev/null; then
  echo 'VERIFIED_COMMIT must resolve to an existing commit' >&2
  exit 1
fi
git checkout --detach "$VERIFIED_COMMIT"
unset VERIFIED_COMMIT
test -z "$(git status --short)"
```

Run `cd cloud` once per host session as shown above. Stay at this repository
root for the rest of the guide; later command blocks intentionally omit a
second `cd cloud`. If you reconnect later, change into `cloud` once before
resuming.

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

## Firewall precondition before installing K3s

Run the following on both `control-1` and `game-1` before installing K3s or
applying either repository firewall script. UFW must be active with
`Default: deny (incoming)`, and the existing operator SSH channel must remain
allowed. The scripts add rules but do not enable UFW, choose an SSH port, or
repair an unsafe SSH policy.

While connected through the SSH channel that must be preserved, inspect and
record the existing rules:

```bash
sudo ufw status numbered
sudo ufw status verbose
```

Identify the exact rule that permits the current SSH source and port. If it is
missing, stop and use the host's established access procedure to add that
specific allow rule before enabling UFW. Do not guess a port or source CIDR.
If the default incoming policy is not deny, set it only after confirming that
SSH rule. If UFW is inactive, enable it only after confirming that rule, then
verify the state:

```bash
sudo ufw default deny incoming
sudo ufw enable
sudo ufw status verbose
test "$(sudo ufw status | awk 'NR == 1 {print $2}')" = active
sudo ufw status verbose | grep -Eq '^Default: deny \(incoming\)'
```

Before applying the repository rules, review `sudo ufw status numbered` for
broad existing rules such as `Anywhere` that expose port 5432, port 6443 or
the configured `CONTROL_API_PORT` outside the intended allowlists. Remove only
an individually identified and reviewed rule through the normal UFW change
procedure; never use `ufw reset` or a blind wildcard deletion. If a numbered
rule must be removed, use an exact reviewed rule number and verify the result:

```bash
read -r -p 'Exact reviewed UFW rule number to remove (empty to skip): ' UFW_RULE_NUMBER
if [[ -n "$UFW_RULE_NUMBER" ]]; then
  [[ "$UFW_RULE_NUMBER" =~ ^[0-9]+$ ]] || {
    echo 'rule number must be decimal' >&2
    exit 1
  }
  sudo ufw delete "$UFW_RULE_NUMBER"
fi
unset UFW_RULE_NUMBER
sudo ufw status numbered
```

Re-run the numbered status and both active/default-policy checks above after
any change. Keep the SSH rule and current channel intact throughout.

The pinned K3s installation also requires UFW to allow the default pod CIDR
`10.42.0.0/16` and service CIDR `10.43.0.0/16` on both hosts. The repository's
[control firewall script](../k3s/firewall-control.sh) and
[game firewall script](../k3s/firewall-game.sh) add those versioned K3s-default
rules while retaining the host-to-host rules above. See the
[K3s networking requirements](https://docs.k3s.io/installation/requirements#networking)
before applying them.

## Expected versions and capture commands

The expected pinned inputs are recorded in the repository files below. These
values are safe to compare with live state because the commands select only
versions, image references and non-secret environment values:

| Component | Repository source | Expected value |
| --- | --- | --- |
| K3s | [`config.example.env`](config.example.env), [`install-control.sh`](../k3s/install-control.sh) and [`install-game.sh`](../k3s/install-game.sh) | `v1.36.4+k3s1` |
| Paper | [`deployment.yaml`](../../catalog/games/minecraft-java/paper/k8s/deployment.yaml) | `itzg/minecraft-server@sha256:efa878ddb49cf5251b2e5f2ad71b08fd2f7236c1f7907433f6697258b31d2ce4`; `VERSION=26.2`; `PAPER_BUILD=121` |
| PostgreSQL | [`control.yaml.template`](templates/control.yaml.template) | `postgres:17.6-bookworm@sha256:f3bd19c606e442c3d7bdfa8002e03fe260a1023351e0ea4598032022b68dd6e3` |
| `cloud-control` | [`deploy.sh`](deploy.sh), [`Dockerfile`](../../apps/cloud-control/Dockerfile) and [`package.json`](../../apps/cloud-control/package.json) | local image `cloud-control:tes-151`; package `0.0.0`; Node `22.20.0-bookworm-slim@sha256:b21fe589dfbe5cc39365d0544b9be3f1f33f55f3c86c87a76ff65a02f8f5848e`, used by both Dockerfile stages |

Capture the source commit on both hosts before installing K3s. Run the first
block on `control-1` and the second block on `game-1`:

```bash
mkdir -p infra/.local/tes-151-versions
git rev-parse HEAD | tee infra/.local/tes-151-versions/control-1-commit.txt
```

```bash
mkdir -p infra/.local/tes-151-versions
git rev-parse HEAD | tee infra/.local/tes-151-versions/game-1-commit.txt
```

Transfer the non-secret `game-1` commit file to the same ignored operator
directory on `control-1` through the authorized SSH channel. On `control-1`,
compare the commits exactly:

```bash
cmp infra/.local/tes-151-versions/control-1-commit.txt \
  infra/.local/tes-151-versions/game-1-commit.txt
```

The `cmp` result proves both hosts use the same repository commit. It does not
print credentials or join tokens. K3s version capture and comparison happen
only after both K3s services have been installed below.

## 3. Install and prepare `control-1`

Run every command in this section on `control-1` from the repository root.
Never enable shell tracing while the local configuration is loaded.

### 3.1 Install the pinned K3s server

Load only the values needed by the installer into the command environment and
run the repository's pinned installer:

```sh
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$CONTROL_NODE_NAME" \
  CONTROL_PRIVATE_ADDRESS="$CONTROL_PRIVATE_ADDRESS" \
  infra/k3s/install-control.sh
)
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

After the UFW precondition passes on `control-1`, apply the repository rules.
They leave existing SSH rules untouched, allow the game source address to
reach the K3s API and WireGuard tunnel, and allow only the configured client
CIDR to reach the control API port:

```sh
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo infra/k3s/firewall-control.sh \
  "$GAME_CLUSTER_SOURCE_ADDRESS" \
  "$CONTROL_API_CLIENT_CIDR" \
  "$CONTROL_API_PORT"
)
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

Run the next commands on `game-1`. The already-privileged installer prompts
on `/dev/tty` for the join token, so the token is never placed in `sudo`
argv:

```bash
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$GAME_NODE_NAME" \
  GAME_NODE_ADDRESS="$GAME_NODE_ADDRESS" \
  K3S_URL="https://$CONTROL_PRIVATE_ADDRESS:6443" \
  infra/k3s/install-game.sh
)
```

Non-interactive automation may instead set `K3S_TOKEN` directly in the root
installer process environment. That compatibility path avoids the prompt; the
interactive guide intentionally does not forward the token through `sudo`.

The agent installer sets `GAME_NODE_ADDRESS` as the node IP and applies the
`cloud.example/role=game` label. The control address used in `K3S_URL` must be
the private address reachable from `game-1`, not a NAT or player-facing value.

### 4.1 Apply the game firewall

Still on `game-1`, allow the WireGuard tunnel from `control-1` and the direct
Minecraft TCP port:

```sh
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo infra/k3s/firewall-game.sh "$CONTROL_PRIVATE_ADDRESS" "$GAME_PORT"
)
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

### 4.3 Capture and compare installed K3s versions

Only after both the server and agent installations have completed, capture
`k3s --version` on each host. Run the first block on `control-1` and the
second on `game-1`; each host must be at the repository root:

```bash
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo k3s --version | tee infra/.local/tes-151-versions/control-1-k3s-version.txt
grep -F "$K3S_VERSION" infra/.local/tes-151-versions/control-1-k3s-version.txt >/dev/null
)
```

```bash
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo k3s --version | tee infra/.local/tes-151-versions/game-1-k3s-version.txt
grep -F "$K3S_VERSION" infra/.local/tes-151-versions/game-1-k3s-version.txt >/dev/null
)
```

Transfer the non-secret `game-1` version file to the same ignored directory
on `control-1` through the authorized SSH channel, then run on `control-1`:

```bash
cmp infra/.local/tes-151-versions/control-1-k3s-version.txt \
  infra/.local/tes-151-versions/game-1-k3s-version.txt
```

The two captures must both contain the pinned `K3S_VERSION`, and `cmp` proves
the installed version output is identical on both hosts. These files contain
no credentials or join token.

## 5. Deploy from `control-1` and verify installation readiness

Run these commands on `control-1`. `deploy.sh` loads the full protected
configuration, creates a temporary Secret input with restrictive permissions,
builds and imports the pinned local `cloud-control` image, and applies the
control, storage and Paper resources:

```sh
(
set -euo pipefail
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
)
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
- the control health endpoint works locally, Paper answers a Minecraft protocol
  status request through `mc-monitor`, and the configured direct game TCP path
  works from `control-1`.

The Paper rollout may wait up to ten minutes, matching its startup probe. The
Pod does not become Ready merely because port 25565 accepts TCP; both rollout
completion and the explicit `mc-monitor` check require a successful Minecraft
status response.

After deploy.sh and verify.sh succeed, capture the effective non-secret image
references and Paper values on control-1:

```bash
mkdir -p infra/.local/tes-151-versions
sudo k3s kubectl get deployment/paper-e0-oracle -n cloud-minecraft-paper \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' \
  | tee infra/.local/tes-151-versions/paper-image.txt
sudo k3s kubectl get deployment/paper-e0-oracle -n cloud-minecraft-paper \
  -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="VERSION")]}{.value}{"\n"}{end}' \
  | tee infra/.local/tes-151-versions/paper-version.txt
sudo k3s kubectl get deployment/paper-e0-oracle -n cloud-minecraft-paper \
  -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="PAPER_BUILD")]}{.value}{"\n"}{end}' \
  | tee infra/.local/tes-151-versions/paper-build.txt
sudo k3s kubectl get statefulset/cloud-postgres -n cloud-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' \
  | tee infra/.local/tes-151-versions/postgres-image.txt
sudo k3s kubectl get deployment/cloud-control -n cloud-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' \
  | tee infra/.local/tes-151-versions/cloud-control-image.txt
sudo k3s ctr images ls | grep 'cloud-control:tes-151' \
  | tee infra/.local/tes-151-versions/cloud-control-import.txt
```

Compare these files privately with the expected values in the table above.
The local cloud-control:tes-151 import record may include an image digest;
keep all captured output in the ignored directory.

From an authorized operator machine, separately check the direct game path and
the private administration boundary. This machine need not have the checkout
or infra/.local/tes-151.env; do not source a repository config from a third
host. The operator must provide these non-secret endpoint values privately:

```bash
(
set -euo pipefail
read -r -p 'Game direct address: ' GAME_DIRECT_ADDRESS
read -r -p 'Game TCP port: ' GAME_PORT
read -r -p 'Control API port: ' CONTROL_API_PORT
read -r -p 'Control address: ' CONTROL_ADDRESS
for port_name in GAME_PORT CONTROL_API_PORT; do
  port_value="${!port_name}"
  case "$port_value" in
    ''|*[!0-9]*)
      echo "$port_name must be a decimal port" >&2
      exit 1
      ;;
  esac
  if [ "$port_value" -lt 1 ] || [ "$port_value" -gt 65535 ]; then
    echo "$port_name must be between 1 and 65535" >&2
    exit 1
  fi
done
nc -vz "$GAME_DIRECT_ADDRESS" "$GAME_PORT"
curl --fail "http://$CONTROL_ADDRESS:$CONTROL_API_PORT/healthz"
if nc -vz -w 3 "$CONTROL_ADDRESS" 5432; then
  echo 'ERROR: PostgreSQL is exposed to the operator probe host' >&2
  exit 1
fi
if nc -vz -w 3 "$CONTROL_ADDRESS" 6443; then
  echo 'ERROR: the K3s API is exposed to the operator probe host' >&2
  exit 1
fi
unset GAME_DIRECT_ADDRESS GAME_PORT CONTROL_API_PORT CONTROL_ADDRESS
)
```

The first probe is the direct player-facing game path. PostgreSQL and K3s
administration remain private; use the control host's authorized local access
for cluster administration. These checks establish installation readiness,
not F2/F3 API behavior or TES-148's complete playable journey.

## 6. Reapply without deleting durable data

Do not use `reset-host.sh` for this gate. It is a destructive dedicated-host
reset that invokes K3s uninstallers and clears only selected data paths; it is
not part of an ordinary reapply.

After the first successful pass, record private probes in the ignored
`infra/.local/tes-151-persistence/` directory. Record identifiers and hashes,
not raw private logs. The SQL below creates a small probe table because the
current F1 application does not own a persistent application schema; it does
not add runtime behavior.

### 6.1 Capture the baseline on `control-1`

Run this on `control-1` from the repository root. It records both PVC/PV UIDs,
creates one uniquely identified PostgreSQL row, and captures its `id|value`
pair:

```sh
(
set -euo pipefail
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

sudo k3s kubectl exec -n cloud-system statefulset/cloud-postgres -- \
  psql -v ON_ERROR_STOP=1 -U cloud -d cloud -c \
  'CREATE TABLE IF NOT EXISTS tes_146_reapply_probe (
     id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     value text NOT NULL
   );'
sudo k3s kubectl exec -n cloud-system statefulset/cloud-postgres -- \
  psql -v ON_ERROR_STOP=1 -U cloud -d cloud -AtF '|' -c \
  "INSERT INTO tes_146_reapply_probe (value)
   VALUES ('tes-146-' || md5(random()::text || clock_timestamp()::text))
   RETURNING id, value;" \
  | tee infra/.local/tes-151-persistence/before/postgres-probe.tsv
test "$(wc -l < infra/.local/tes-151-persistence/before/postgres-probe.tsv | tr -d ' ')" = 1
cut -d '|' -f 1 infra/.local/tes-151-persistence/before/postgres-probe.tsv \
  > infra/.local/tes-151-persistence/before/postgres-probe.id
cut -d '|' -f 2- infra/.local/tes-151-persistence/before/postgres-probe.tsv \
  > infra/.local/tes-151-persistence/before/postgres-probe.value
)
```

The generated row is not a password or machine token. Keep the captured ID
and value in the ignored directory; the `id` is the identity used for the
after-reapply query.

### 6.2 Stop Paper from `control-1`

Run this on `control-1`. K3s administration remains private to the control
host. Scaling the Deployment to zero and waiting for the existing Pod to
terminate ensures the marker can be written while Paper is not using the data
path:

```sh
PAPER_POD="$(sudo k3s kubectl get pod -n cloud-minecraft-paper \
  -l app=paper-e0-oracle -o jsonpath='{.items[0].metadata.name}')"
test -n "$PAPER_POD"
sudo k3s kubectl scale deployment/paper-e0-oracle \
  -n cloud-minecraft-paper --replicas=0
sudo k3s kubectl wait --for=delete "pod/$PAPER_POD" \
  -n cloud-minecraft-paper --timeout=180s
```

Now run this marker block on `game-1`:

```sh
(
set -euo pipefail
mkdir -p infra/.local/tes-151-persistence/before
set -a
. infra/.local/tes-151.env
set +a
MARKER_PATH="$GAME_DATA_PATH/.tes-151-reapply-marker"
MARKER_VALUE="$(openssl rand -hex 16)"
printf '%s\n' "$MARKER_VALUE" | sudo tee "$MARKER_PATH" >/dev/null
sudo sha256sum "$MARKER_PATH" \
  > infra/.local/tes-151-persistence/before/world-marker.sha256
unset MARKER_VALUE
)
```

The marker remains below the configured game data path. The private hash is
the durable-world probe; do not commit the marker value or any host output.

### 6.3 Repeat installation without `reset-host.sh`

Use the same verified commit and configuration values, and run the commands in
this order. Run the first block on `control-1`:

```bash
(
set -euo pipefail
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
)
```

Run the next block on `game-1`. Transfer the current join token through the
same protected prompt used for the first installation; never put it in the
commands below, a file or a log:

```bash
(
set -euo pipefail
set -a
. infra/.local/tes-151.env
set +a
sudo env \
  K3S_VERSION="$K3S_VERSION" \
  NODE_NAME="$GAME_NODE_NAME" \
  GAME_NODE_ADDRESS="$GAME_NODE_ADDRESS" \
  K3S_URL="https://$CONTROL_PRIVATE_ADDRESS:6443" \
  infra/k3s/install-game.sh
sudo infra/k3s/firewall-game.sh "$CONTROL_PRIVATE_ADDRESS" "$GAME_PORT"
sudo infra/two-host/prepare-host.sh game infra/.local/tes-151.env
)
```

Finish on `control-1` so the Deployment recreates Paper and all three
workloads return to Ready:

```sh
(
set -euo pipefail
sudo infra/two-host/deploy.sh infra/.local/tes-151.env
sudo infra/two-host/verify.sh infra/.local/tes-151.env
)
```

### 6.4 Capture and compare the after state

On `control-1`, create `after/`, capture the same PVC/PV identities, query the
same PostgreSQL row by its saved ID, and compare the exact `id|value` pair:

```sh
(
set -euo pipefail
mkdir -p infra/.local/tes-151-persistence/after
for claim in cloud-system/cloud-postgres-data cloud-minecraft-paper/paper-e0-oracle-data; do
  namespace="${claim%/*}"
  name="${claim#*/}"
  sudo k3s kubectl get pvc "$name" -n "$namespace" -o jsonpath='{.metadata.uid}{"\n"}' \
    > "infra/.local/tes-151-persistence/after/${namespace}-${name}.pvc.uid"
done
for volume in cloud-postgres-data cloud-paper-data; do
  sudo k3s kubectl get pv "$volume" -o jsonpath='{.metadata.uid}{"\n"}' \
    > "infra/.local/tes-151-persistence/after/${volume}.pv.uid"
done
POSTGRES_PROBE_ID="$(cat infra/.local/tes-151-persistence/before/postgres-probe.id)"
case "$POSTGRES_PROBE_ID" in
  ''|*[!0-9]*)
    echo "invalid PostgreSQL probe ID" >&2
    exit 1
    ;;
esac
sudo k3s kubectl exec -n cloud-system statefulset/cloud-postgres -- \
  psql -v ON_ERROR_STOP=1 \
  -U cloud -d cloud -AtF '|' -c \
  "SELECT id, value FROM tes_146_reapply_probe WHERE id = ${POSTGRES_PROBE_ID};" \
  > infra/.local/tes-151-persistence/after/postgres-probe.tsv
cut -d '|' -f 1 infra/.local/tes-151-persistence/after/postgres-probe.tsv \
  > infra/.local/tes-151-persistence/after/postgres-probe.id
cut -d '|' -f 2- infra/.local/tes-151-persistence/after/postgres-probe.tsv \
  > infra/.local/tes-151-persistence/after/postgres-probe.value
cmp infra/.local/tes-151-persistence/before/postgres-probe.tsv \
  infra/.local/tes-151-persistence/after/postgres-probe.tsv
diff -ru infra/.local/tes-151-persistence/before/ \
  infra/.local/tes-151-persistence/after/
)
```

On `game-1`, create the matching `after/` directory, capture the marker hash,
and compare it with the baseline:

```sh
(
set -euo pipefail
mkdir -p infra/.local/tes-151-persistence/after
set -a
. infra/.local/tes-151.env
set +a
MARKER_PATH="$GAME_DATA_PATH/.tes-151-reapply-marker"
sudo sha256sum "$MARKER_PATH" \
  > infra/.local/tes-151-persistence/after/world-marker.sha256
diff -ru infra/.local/tes-151-persistence/before/ \
  infra/.local/tes-151-persistence/after/
)
```

The reapply gate passes only when both directory comparisons and the
PostgreSQL `cmp` succeed, the saved PVC/PV identities are unchanged, the
PostgreSQL probe row still has the same ID and value, the world marker hash is
unchanged, and `verify.sh` reports the PostgreSQL, `cloud-control` and Paper
workloads Ready. The saved ID is validated as decimal before safe shell
interpolation into the SQL, so this query does not rely on `psql -v` variable
substitution. A second `deploy.sh` applies resources and restarts the
stateless control process; it does not delete durable PVCs or host data paths.

The [TES-151 live installation evidence](../evidence/tes-151-two-host-installation.md)
records an existing two-host result with the same persistence checks. It is a
reference for the installation gate, not a place to copy private addresses,
credentials, provider identifiers or raw logs.

## Verify the control service account

The deployment grants `cloud-control` these Kubernetes permissions:

| Scope | Resources | Operations |
| --- | --- | --- |
| `cloud-minecraft-paper` | Deployments, PVCs and Services | Get, list, create and patch |
| `cloud-minecraft-paper` | Pods | Get and list |
| Cluster | Nodes | Get and list |

The control Pod receives a projected Kubernetes service-account token. This
token is separate from the caller's machine token. PostgreSQL and Paper keep
token mounting disabled; the control account cannot read Secrets, change
other namespaces, modify nodes or RBAC, or delete retained PVCs. See the
Kubernetes documentation for [service-account token mounting](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
and [RBAC scope](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

From the repository root on `control-1`, while the fixed Paper workload is
running, first confirm that no players will be interrupted and that the game
container has no mounted Kubernetes token:

```sh
sudo k3s kubectl exec -n cloud-minecraft-paper deployment/paper-e0-oracle -- \
  mc-monitor status --host 127.0.0.1 --port 25565 | grep ' online=0 '
sudo k3s kubectl exec -n cloud-minecraft-paper deployment/paper-e0-oracle -- \
  test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token
```

Continue only if both commands succeed. The following probe runs inside the
control Pod and uses its projected token and cluster CA without printing
either. It checks allowed reads, three creation requests using Kubernetes
server dry-run, six forbidden operations, and a real stop/start of Paper:

```sh
sudo k3s kubectl exec -i -n cloud-system deployment/cloud-control -- \
  node --input-type=module < infra/two-host/verify-rbac.mjs
```

The stop/start check waits for the old Pod to disappear before starting a
replacement and requiring Ready. If stopping fails, it attempts to restore
one replica. Inspect the workload before retrying a failed probe. This checks
the service account's runtime access; the product lifecycle API is TES-69
and F3 work.

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
