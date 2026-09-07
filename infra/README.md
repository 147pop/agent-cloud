# Infrastructure

The first reproducible foundation uses `control-1` for cloud-control, PostgreSQL and the K3s server, and `game-1` for the K3s agent, Paper and persistent worlds. [two-host/](two-host/) packages that installation from a clean checkout; [k3s/](k3s/) contains the pinned cluster installer. Token enforcement and the complete agent-to-play flow remain to be implemented in F2/F3.

Foundation acceptance uses a direct game IP and port or DNS-only address. A temporary second game worker for disaster recovery and Cloudflare routing belong to the later managed service. Spectrum is the final gate before public opening.

Read the [architecture](../docs/architecture.md) before adding reusable infrastructure configuration. Put server recipes in the [catalog](../catalog/README.md) and measurement code with the [benchmarks](../benchmarks/README.md).

The dated host inventory, SSH destinations, firewall records and provider identifiers are preserved in the private operator archive attached to [TES-53](https://linear.app/workspace/issue/TES-53). Private keys remain outside Git and Linear. Verify live host state before operating a server.

Historical Git commits and raw E0 measurements still contain operational identifiers. The [public release review](https://linear.app/workspace/issue/TES-138) must resolve their publication before the repository changes visibility.
