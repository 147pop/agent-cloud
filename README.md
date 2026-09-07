# Cloud

Cloud is a project for hosting game servers and curated applications on managed infrastructure. **Host** covers games. **Deploy** covers applications. The first delivery is a reproducible Minecraft Java foundation on two real hosts. It must turn one complete agent request into a playable server, preserve its world, and expose the same lifecycle through API, MCP and a CLI client.

The project is in pre-beta development. This repository contains benchmark tools and evidence, the selected Paper profile, a K3s installer and runtime manifests, a minimal TypeScript `cloud-control` application, design records and product prototypes. It does not yet contain a working request-to-play platform.

## Start here

| Read | Find |
| --- | --- |
| [Architecture](docs/architecture.md) | How the two-host foundation and later managed service are intended to work |
| [Decisions](docs/decisions.md) | Chosen directions, replaced assumptions and open decisions |
| [Catalog](catalog/README.md) | Recipes, tested profiles and the requirements for offering them |
| [Minecraft benchmarks](benchmarks/minecraft/README.md) | Recorded results, their limits and reproduction instructions |
| [Infrastructure](infra/README.md) | Reusable infrastructure material and operator records |
| [Contributing](CONTRIBUTING.md) | Local checks, changes and evidence for review |

## Delivery plan

The [Cloud reproducible Minecraft foundation](https://linear.app/workspace/project/cloud-reproducible-minecraft-foundation-b16cc0163842) project follows these results in order:

| Delivery | Required result |
| --- | --- |
| Evidence and selected profile | Preserve the completed two-host inventory and benchmark evidence and the selected Paper profile without treating them as platform proof |
| Repository and two-host installation | From a clean clone, install `control-1` and `game-1` with operator-owned credentials |
| Control plane and Kubernetes | Deploy the TypeScript `cloud-control`, PostgreSQL, K3s server, K3s agent, Paper and persistent world resources |
| Agent access and warm allocation | Expose one lifecycle contract through API and MCP, use it from the CLI, and prove cold start and ready unowned warm assignment in separate trials |
| Two-host acceptance | Complete an agent request to a playable endpoint and prove readiness, ownership, persistence, durable idempotency, control restart and bounded admission |
| [Code publication](https://linear.app/workspace/project/cloud-public-source-release-02a68856fb69) | Publish the foundation code, two-host deployment instructions and evidence after a clean clone can reproduce the bounded result |
| [Managed Minecraft beta](https://linear.app/workspace/project/cloud-managed-minecraft-beta-b8f51ce201e3) | Add public registration, managed edge access, public operating limits and disaster recovery, then use Cloudflare Spectrum as the final public-opening gate |
| [Paid game catalog](https://linear.app/workspace/project/cloud-paid-game-catalog-7f20b95b4b7f) | Qualify more engines, configurations and games; measure cost and introduce billing against those profiles |
| [Curated application hosting](https://linear.app/workspace/project/cloud-curated-application-hosting-fdd65aa7ca8c) | Qualify applications for their own persistence, networking, availability and recovery needs |

The selected profile uses Paper 26.2 build 121 with two CPU quota units, a 2 GiB heap and a 3 GiB total container RAM limit. The owner accepted the [repeated two-player bot and local recovery results](benchmarks/minecraft/free-profile-results.md) for one running instance with two players on the tested Oracle A1 host. A ready warm instance consumes that one qualified slot. Cold and warm paths can pass in separate trials. Refilling the warm slot while an owned server remains active needs new capacity evidence. The failed two-active-instance run does not decide whether an active server can coexist with an idle warm server. The profile's 4 GB world soft limit and the recipe's 10 GiB PVC request do not enforce or prove a storage quota.

The first playable endpoint may be a directly reachable worker IP and port or a DNS-only address. It is returned only after Minecraft accepts a protocol connection. Cloudflare Worker, Tunnel, Access and Spectrum belong to the later managed public service. Spectrum and authenticated external play are final checks before public opening. Official Vanilla is planned as a later paid option.

Deploy starts with applications maintained in the catalog. Arbitrary user images and repositories need a later isolation design. Agent hosting, previously called Continue, is outside the current scope.

## Project records

GitHub holds the design, runnable configuration and published evidence. The [Cloud delivery map](https://linear.app/workspace/document/cloud-delivery-map-c0e6db580d08) holds delivery planning, responsibility and work in progress. A public result must remain understandable without Linear access.

Git history preserves earlier designs. The [landing](prototypes/landing/index.html) and [technical brief](prototypes/technical-brief/index.html) are historical prototypes.

Cloud is a project by Pablo Cardozo and Agustín Pedernera. The [Git history](https://github.com/pjcdz/cloud/graphs/contributors) records code contributions. The foundation must be reproducible before publication. A clean clone, two compatible hosts and operator-owned credentials must produce the bounded request-to-play result using the published instructions. This does not promise the later managed public service. The code is licensed under [MIT](LICENSE); third-party code and asset review still gates publication (see [Contributing](CONTRIBUTING.md)).

For security concerns, read [SECURITY.md](SECURITY.md).
