# Cloud

Cloud is a project for running game servers and curated applications. **Host** covers games. **Deploy** covers applications. Development now starts with a complete local product; the managed service is an adapter and operating layer built on that accepted core.

The project is in pre-beta development. This repository currently contains runnable benchmark tools, candidate Minecraft recipes, measurements and product prototypes. The root `cloud-control` application, local Docker runtime, account service, queue, MCP API and managed Kubernetes deployment are still planned. The next delivery gate is a clean clone completing `create → start → status → connect → stop` locally without cloud credentials.

The planned local entry point is `docker compose up --build`. It will bind every exposed port to loopback and run a containerized `cloud-control` with development-only access to the Docker Engine. This command does not exist yet; TES-150 is active and TES-151 follows it.

## Start here

| Read | Find |
| --- | --- |
| [Architecture](docs/architecture.md) | How the local product becomes the managed service |
| [Decisions](docs/decisions.md) | Chosen directions, replaced assumptions and open decisions |
| [Catalog](catalog/README.md) | Recipes, tested profiles and the requirements for offering them |
| [Minecraft benchmarks](benchmarks/minecraft/README.md) | Recorded results, their limits and reproduction instructions |
| [Infrastructure](infra/README.md) | Reusable infrastructure material and operator records |
| [Contributing](CONTRIBUTING.md) | Local checks, changes and evidence for review |

## Delivery plan

| Delivery | Required result |
| --- | --- |
| [Local Minecraft MVP](https://linear.app/workspace/project/cloud-local-minecraft-mvp-b16cc0163842) | Start from a clean clone and complete the full request-to-play flow with PostgreSQL, Docker and persistent local data |
| [Managed Minecraft beta](https://linear.app/workspace/project/cloud-managed-minecraft-beta-b8f51ce201e3) | Adapt the accepted local core to Kubernetes, identity, Cloudflare, admission, remote backup and invited-user operations |
| [Paid game catalog](https://linear.app/workspace/project/cloud-paid-game-catalog-7f20b95b4b7f) | Qualify more engines, configurations and games; measure cost and introduce billing against those profiles |
| [Curated application hosting](https://linear.app/workspace/project/cloud-curated-application-hosting-fdd65aa7ca8c) | Qualify applications for their own persistence, networking, availability and recovery needs |
| [Code publication](https://linear.app/workspace/project/cloud-public-source-release-02a68856fb69) | After local acceptance, publish a licensed repository with reproducible instructions, contribution history and a private security reporting channel |

Code publication and managed-service adaptation are parallel tracks after the local acceptance gate; neither blocks the other.

The free profile uses Paper 26.2 build 121 with two CPU quota units, a 2 GiB heap and a 3 GiB container limit. The owner accepted the [repeated two-player bot and recovery results](benchmarks/minecraft/free-profile-results.md) for E1, with one active instance on the tested Oracle A1 host. Platform lifecycle and recovery still need their own acceptance. Cloudflare Spectrum and authenticated external play are final checks before opening the product publicly. Official Vanilla is planned as a later paid option.

Deploy starts with applications maintained in the catalog. Arbitrary user images and repositories need a later isolation design. Agent hosting, previously called Continue, is outside the current scope.

## Project records

GitHub holds the design, runnable configuration and published evidence. [Linear](https://linear.app/workspace/document/cloud-organization-and-catalog-plan-c0e6db580d08) holds delivery planning, responsibility and work in progress. A public result must remain understandable without Linear access.

Git history preserves earlier designs. The [landing](prototypes/landing/index.html) and [technical brief](prototypes/technical-brief/index.html) are historical prototypes.

Cloud is a project by Pablo Cardozo and Agustín Pedernera. The [Git history](https://github.com/pjcdz/cloud/graphs/contributors) records code contributions. The plan is to make a clean clone work locally before publishing the source or offering the managed service. A supported production installation on third-party infrastructure remains a later delivery. The code is licensed under [MIT](LICENSE); third-party code and asset review still gates the actual publication (see [Contributing](CONTRIBUTING.md)).

For security concerns, read [SECURITY.md](SECURITY.md).
