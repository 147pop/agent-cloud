# Infrastructure

The first reproducible foundation uses `control-1` for cloud-control, PostgreSQL and the K3s server, and `game-1` for the K3s agent, Paper and persistent worlds. The [two-host clean-clone quickstart](two-host/README.md) is the canonical F1 installation and safe-reapply guide; [k3s/](k3s/) contains the pinned cluster installer. Token enforcement and the complete agent-to-play flow remain F2/F3 work, with the complete playable journey accepted separately by TES-148.

Foundation acceptance uses a direct game IP and port or DNS-only address. A temporary second game worker for disaster recovery and Cloudflare routing belong to the later managed service. Spectrum is the final gate before public opening.

Read the [architecture](../docs/architecture.md) before adding reusable infrastructure configuration. Put server recipes in the [catalog](../catalog/README.md) and measurement code with the [benchmarks](../benchmarks/README.md).

The dated host inventory, SSH destinations, firewall records and provider identifiers are preserved in the private operator archive attached to TES-53. Private keys remain outside Git and Linear. Verify live host state before operating a server.

The published history was sanitized before release: operator addresses, hostnames, SSH aliases and personal e-mails were replaced with neutral placeholders, and the affected checksum manifests were reissued. See the [public release record](evidence/tes-139-public-release.md).
