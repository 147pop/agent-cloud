# K3s installer (TES-59, TES-25)

One K3s server on `control-1`, one agent on `game-1`, joined over flannel's
`wireguard-native` backend. No script here takes or stores a host IP,
SSH credential, or join token as a literal — everything host-specific is
passed as an argument or environment variable at run time, per
[infra/README.md](../README.md)'s rule against operational identifiers in Git.

## Order of operations

1. On `control-1` (sudo), set `CONTROL_PRIVATE_ADDRESS`, and optionally
   `NODE_NAME` and the exact `K3S_VERSION`, then run `./install-control.sh`.
   It installs the K3s server with the `wireguard-native` flannel backend,
   disables the bundled Traefik and ServiceLB. The current Paper manifest
   exposes `hostPort` for direct test connections; Spectrum is a later public-opening gate. It tags the node
   `cloud.example/role=control:NoSchedule` so no game workload can land there,
   and records the token path without printing the token. Read the token
   out-of-band — do not paste it into a commit, issue, PR, or captured log.

2. On `game-1` (sudo):
   ```sh
   K3S_URL=https://<control-1-ip>:6443 K3S_TOKEN=<token from step 1> \
     GAME_NODE_ADDRESS=<game-1-interface-ip> ./install-game.sh
   ```
   Installs the K3s agent and labels the node `cloud.example/role=game` —
   the same label [../../catalog/games/minecraft-java/paper/k8s/deployment.yaml](../../catalog/games/minecraft-java/paper/k8s/deployment.yaml)'s
   `nodeSelector` targets.

3. On `control-1`: `./firewall-control.sh <game-1-source-ip> <api-client-cidr> <api-port>`
   On `game-1`: `./firewall-game.sh <control-1-ip> <game-port>`
   Restricts the K3s API (6443/tcp) and the flannel wireguard tunnel
   (51820/udp) to the other node's routable or NAT source IP only, via `ufw`.
   The game agent's `GAME_NODE_ADDRESS` is separately the IPv4 address assigned
   to its local interface. The firewall also restricts the
   control API to the configured client CIDR and opens the configured direct
   Minecraft port. Existing SSH rules remain untouched.

   Both hosts also sit behind provider-level firewalls (OCI security
   list/NSG for `game-1`, per TES-53) — this repo has no credentials to
   change those, so open the matching 51820/udp rule there too, out of band.

4. On `control-1`: `./verify.sh`
   Confirms both nodes `Ready`, the control taint present, and the game
   label present.

## TES-59 done criteria

- [ ] Both nodes `Ready` (`verify.sh`)
- [ ] No game workload can land on `control-1` (taint from step 1; nothing in
      this catalog's manifests carries a matching toleration, so the default
      `NoSchedule` behavior holds)
- [ ] Configuration recorded without credentials (this directory — the token
      and IPs never appear here, only in the private TES-53 archive)

## TES-25 done criteria

- [ ] Cluster ports (6443/tcp, 51820/udp) reachable only between `control-1`
      and `game-1` — `ufw status verbose` on each host after step 3, plus the
      provider-level firewall confirmed out of band.

## What this doesn't do

No Terraform/Ansible, no HA control plane, no second game worker (that's
TES-92 for the recovery drill, later). This is the official K3s install
script (`get.k3s.io`) run twice with the right flags — the smallest thing
that satisfies TES-59/TES-25, not a general-purpose provisioning system.
