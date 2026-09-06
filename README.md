# Cloud

Cloud is a project for hosting game servers and curated applications on managed infrastructure. **Host** covers games. **Deploy** covers applications. The first delivery is a free Minecraft Java beta, with persistent worlds and a server configuration chosen for efficient use of shared hosts.

The project is in pre-beta development. This repository contains runnable benchmark tools, candidate Minecraft recipes, measurements and product prototypes. The account service, queue, MCP API and managed Kubernetes deployment are still planned.

## Start here

| Read | Find |
| --- | --- |
| [Architecture](docs/architecture.md) | How the first managed service is intended to work |
| [Decisions](docs/decisions.md) | Chosen directions, replaced assumptions and open decisions |
| [Catalog](catalog/README.md) | Recipes, tested profiles and the requirements for offering them |
| [Minecraft benchmarks](benchmarks/minecraft/README.md) | Recorded results, their limits and reproduction instructions |
| [Infrastructure](infra/README.md) | Reusable infrastructure material and operator records |
| [Contributing](CONTRIBUTING.md) | Local checks, changes and evidence for review |

## Delivery plan

| Delivery | Required result |
| --- | --- |
| [Free Minecraft beta](https://linear.app/workspace/project/cloud-free-minecraft-beta-b8f51ce201e3) | Choose an efficient profile, preserve worlds, complete the request-to-play flow, control admission, and demonstrate recovery with invited users |
| [Paid game catalog](https://linear.app/workspace/project/cloud-paid-game-catalog-7f20b95b4b7f) | Qualify more engines, configurations and games; measure cost and introduce billing against those profiles |
| [Curated application hosting](https://linear.app/workspace/project/cloud-curated-application-hosting-fdd65aa7ca8c) | Qualify applications for their own persistence, networking, availability and recovery needs |
| [Code publication](https://linear.app/workspace/project/cloud-public-source-release-02a68856fb69) | Publish a licensed repository with reproducible development instructions, contribution history and a private security reporting channel |

The free profile uses Paper 26.2 build 121 with two CPU quota units, a 2 GiB heap and a 3 GiB container limit. The owner accepted the [repeated two-player bot and recovery results](benchmarks/minecraft/free-profile-results.md) for E1, with one active instance on the tested Oracle A1 host. Platform lifecycle and recovery still need their own acceptance. Cloudflare Spectrum and authenticated external play are final checks before opening the product publicly. Official Vanilla is planned as a later paid option.

Deploy starts with applications maintained in the catalog. Arbitrary user images and repositories need a later isolation design. Agent hosting, previously called Continue, is outside the current scope.

## Project records

GitHub holds the design, runnable configuration and published evidence. [Linear](https://linear.app/workspace/document/cloud-organization-and-catalog-plan-c0e6db580d08) holds delivery planning, responsibility and work in progress. A public result must remain understandable without Linear access.

Git history preserves earlier designs. The [landing](prototypes/landing/index.html) and [technical brief](prototypes/technical-brief/index.html) are historical prototypes.

Cloud is a project by Pablo Cardozo and Agustín Pedernera. The [Git history](https://github.com/pjcdz/cloud/graphs/contributors) records code contributions. The plan is to publish the code first and support installation by third parties later. The code is licensed under [MIT](LICENSE); third-party code and asset review still gates the actual publication (see [Contributing](CONTRIBUTING.md)).

For security concerns, read [SECURITY.md](SECURITY.md).
