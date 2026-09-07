# TES-151 two-host deployment design

## Objective

Make the repository install the F1 control and game services on the dedicated
`control-1` and `game-1` hosts from a clean checkout. The installation must be
repeatable without losing PostgreSQL or Minecraft data, and its published
evidence must contain no operational identifiers or credentials.

## Selected architecture

K3s remains the single production runtime. `control-1` runs the K3s server, a
single PostgreSQL instance and the minimal `cloud-control` Deployment.
`game-1` runs the K3s agent and the pinned Paper Deployment. Node selectors and
the existing control taint keep each workload on its intended host.

The repository provides host bootstrap scripts, Kubernetes manifests and an
operator entry point. A local, ignored configuration file supplies SSH targets,
host addresses, persistent paths, ports and credentials. Checked-in example
configuration documents every input without containing usable values.

The K3s version and container image identities are pinned. The operator builds
the repository's `cloud-control` image on `control-1`, imports it into K3s's
containerd and applies the control resources. Paper uses the selected image
digest and profile already recorded by the repository.

## Persistence and configuration

PostgreSQL and Paper use explicit local persistent volumes with `Retain`
semantics. Their host paths and capacities are configuration inputs. The setup
creates only the selected paths and never removes them during an ordinary
reapply.

The game CPU request and limit, Java heap, container memory and world storage
budget remain separate values. Verification reports those values together with
the capacity left for the host and K3s. A PVC request is documented as a storage
budget, not an enforced filesystem quota.

A real database password and machine token are read from the ignored operator
configuration and written to Kubernetes Secrets. No secret is accepted as a
command-line argument, rendered into a checked-in file or printed by the
verification commands.

## Network and trust boundaries

The Kubernetes API and WireGuard ports remain restricted to the two hosts.
PostgreSQL has a cluster-internal service only. The control HTTP port is opened
only to an operator-configured client CIDR; the Minecraft TCP port is opened on
`game-1` as the direct foundation path. The current health boundary may be
checked remotely, while token enforcement and lifecycle operations remain F2
and F3 work.

Minecraft runs without a Kubernetes API token or RBAC binding. `cloud-control`
receives the machine-token and database inputs but does not receive cluster
administrator credentials in this task.

## Installation and destructive boundary

Fresh-host validation may remove the existing dedicated K3s installation and
the current Paper world, as approved by the owner. Before removal, verification
must confirm that the cluster has no non-system workloads outside the selected
Paper namespace. The destructive reset is a separate, explicit operator action;
the normal setup command is idempotent and non-destructive.

The reset may remove K3s state and the configured TES-151 data paths. It must not
remove unrelated directories, alter provider firewall rules or expose private
host details.

## Verification and evidence

The first pass starts from a clean checkout and a reset K3s installation. It
records sanitized host compatibility, deployed versions, node roles, workload
placement, readiness, resource settings, persistent paths by logical name,
storage budget, host reserve and the direct network path.

The verifier then creates durable probes in PostgreSQL and the Paper volume,
runs the ordinary setup a second time and proves that both probes and the bound
volumes remain. It also checks that PostgreSQL is not externally exposed, the
Kubernetes identities are scoped as designed and the expected ports are bound.

Repository checks include the root TypeScript check, shell syntax and tests,
Kubernetes client-side validation where available, the Minecraft summarizer
self-test, diff inspection and confirmation that the benchmark package and
lockfile did not change. Exact private output belongs in Linear or the ignored
operator evidence directory; Git receives only a sanitized summary.
