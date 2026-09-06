# Decisions

This file records the current direction without requiring access to the planning system. Implementation evidence belongs with the component or benchmark that produced it. Work assignments and discussion belong in Linear.

## Product direction, 2026-09-05

The product owner settled these choices while revising the Cloud organization plan.

| Decision | Reason and consequence |
| --- | --- |
| Keep Host and Deploy in the product | Minecraft is the first delivery. Games and curated applications remain visible in the roadmap without implying that they are implemented. |
| Exclude Continue for now | Agent-hosting environments are outside the current product work. Using an agent as a Cloud client remains in scope. |
| Optimize the free Minecraft offer for efficiency | A familiar game experience with documented differences is acceptable. Compare optimized engines and measure concurrent server density before choosing the default. |
| Place official Vanilla in the later paid catalog | Strict Vanilla behavior may require a different resource profile. Payment does not remove its qualification requirements. |
| Start Deploy with a curated catalog | The team can define and test how each application starts, persists and recovers. Arbitrary images and repositories require a later isolation design. |
| Earlier publication sequence, superseded 2026-09-06 | The earlier plan published inspectable code before supporting installation. The current foundation gate below requires reproducible two-host instructions and evidence before publication. |
| Make GitHub understandable without Linear | Technical decisions and published results have a public home. Linear links to those records and tracks execution. |

## Reproducible foundation scope, 2026-09-06

The first delivery is a reproducible Minecraft foundation on `control-1` and `game-1`. This replaces the earlier Docker-local MVP and code-first publication sequence. It does not replace the accepted Paper profile or the later managed-service decisions.

| Decision | Reason and consequence |
| --- | --- |
| Use K3s as the first actual runtime | `control-1` runs the K3s server, PostgreSQL and the TypeScript `cloud-control` process. `game-1` runs the K3s agent, Paper and the persistent world. Local tools may support development but do not prove or gate two-host acceptance. |
| Qualify one lifecycle contract | An agent must complete `create`, `start`, `status` and `stop` through API or MCP and receive a playable endpoint after protocol readiness. The CLI calls the same API. A separate CLI architecture and a web interface are not prerequisites. |
| Prove cold start and warm assignment | A ready warm instance must be unowned and clean before assignment. Assignment binds it and its world to one owner. Existing servers restart with their own data. The current profile lets cold and warm paths pass in separate trials because the running warm instance consumes the one qualified slot. |
| Keep the direct path small | The reachable API uses machine-token authentication and scoped Kubernetes RBAC. RCON, PostgreSQL and cluster administration stay private. Player TCP goes directly to a reachable worker IP and port or a DNS-only address. |
| Bound accepted capacity | Current evidence covers one running Paper instance with two players. The platform must reject or defer work instead of oversubscribing. It cannot refill a warm spare beside an owned active instance without new capacity and latency evidence. The failed two-active run does not prove that active-plus-idle-warm is impossible. |
| Publish a reproducible bounded result | A clean clone, two compatible hosts and operator-owned credentials must reproduce the foundation using the published code and instructions. The release includes the evidence. It does not promise the managed public service. |
| Defer managed public-service gates | Cloudflare Worker, Tunnel, Access and Spectrum, public registration, billing, public operating scale and remote disaster recovery follow the foundation. Spectrum remains the final gate before public opening. |

Ownership, requested state and idempotency survive a `cloud-control` restart. REST and MCP use the same durable `client_request_id` semantics. Warm capacity never reuses another owner's world.

The selected profile has a 4 GB world soft limit and the K3s manifest requests a 10 GiB PVC. These values do not enforce or prove a storage quota. Storage admission must protect the host until a per-server quota mechanism is qualified.

## Selected technical design

The 2026-09-03 design narrowed the original plan. The [architecture](architecture.md) carries forward these choices.

| Selected | Previous design | Why |
| --- | --- | --- |
| One TypeScript `cloud-control` process with PostgreSQL | Retained from the original plan | Ownership, lifecycle and request state can share one process and durable database state. |
| Deployment with zero or one replicas and an explicit PVC | StatefulSet wording in the original plan | The first workload needs one process and a persistent directory. Stop and replacement tests must still establish one active writer. |
| Local PVC in the foundation; R2 backup and operated recovery later | Longhorn required before a second worker | First prove persistence on `game-1`. Measure remote restore time and lost progress before adding replicated storage or making recovery claims. |
| Polling for later queue and status clients | Server-Sent Events in the original plan | Durable state matters first. The traffic has not justified another transport. A web status page does not gate the foundation. |
| Agent API and MCP as the first acceptance client; CLI on the same API | Simultaneous support claims for several clients | The first proof covers one complete request-to-play flow without adding a separate client architecture. |
| A free invited beta before billing, retained for the managed service | Payment behavior included in the first product path | Establish persistence, recovery, usage and costs before charging for them. |

Git history preserves earlier designs. In particular, the previous Docker Sandboxes and Continue plan does not prescribe Deploy's runtime.

## Managed invited-beta rules, 2026-09-04

Agustín Pedernera recorded these approvals in the decision issues. The later bilingual update replaces the original Spanish-only audience description. The rules remain valid for the managed invited beta, but they no longer define acceptance for the earlier two-host foundation.

| Decision | Accepted rule |
| --- | --- |
| [D1, scope](https://linear.app/workspace/issue/TES-15) | Account, EULA, MCP token, create, start, status, stop, stable address, queue, confirmation, AutoStop, persistence, automatic backup and operator-run restore. User-selected versions, plugins, console, world import and self-service restore follow later. |
| [D2, audience](https://linear.app/workspace/issue/TES-16) | Known users, English and Spanish, at most 20 accounts, two weeks. |
| [D3, free rules](https://linear.app/workspace/issue/TES-17) | One logical server and one active server per account, 4 GB soft storage threshold, five-minute AutoStop, five-minute turn confirmation and operator-confirmed deletion before replacement. |
| [D4, recovery](https://linear.app/workspace/issue/TES-19) | The protection target is the last clean stop. Managed recovery acceptance must measure recovery before any duration is promised. The target does not guarantee preservation of an unfinished session. |
| [D6, client](https://linear.app/workspace/issue/TES-20) | Codex with a revocable bearer token is the first client to qualify through the complete managed request-to-play journey. |
| [D7, billing](https://linear.app/workspace/issue/TES-21) | The first beta is free. Billing follows 100 real runs, proven recovery between workers and measured costs. |
| [D8, availability](https://linear.app/workspace/issue/TES-22) | Accept one control host for the invited beta, conditional on restoring it on a clean host and assigning an incident owner before opening the beta. |

These are acceptance rules, not completed test results. [D9's authorizations and incident ownership](https://linear.app/workspace/issue/TES-23) remain in the private project record.

## Free Paper profile, accepted 2026-09-06

Pablo accepted the repeated bot workload and local recovery evidence for TES-144 and TES-140. This replaces the earlier requirement for a human session before profile selection. The [results](../benchmarks/minecraft/free-profile-results.md#tps-by-player-activity) show active exploration in separate terrain, combat and block actions in two repetitions.

| Decision | Reason and consequence |
| --- | --- |
| Use Paper 26.2 build 121 with the tested free configuration | Two CPU quota units, 2 GiB heap, 3 GiB total container RAM, `ActiveProcessorCount=2`, view 6, simulation 4, seed 20260904 and no gameplay plugins. The 3 GiB value is not a disk limit. |
| Accept one running instance with two players on the tested Oracle A1 host | Both repetitions passed exploration, combat and local recovery. Two instances failed the control-response threshold during a save. Four or eight players in one instance were not tested with this recipe. |

The profile is selected for the foundation. The [K3s recipe](../catalog/games/minecraft-java/paper/k8s/) uses the accepted game settings; its lifecycle checks, platform backups and recovery remain separate work. This decision does not claim human-client, warm-plus-active capacity or public-route evidence.

## D5, public game TCP and worker IP exposure, updated 2026-09-06

The earlier comments in [TES-18](https://linear.app/workspace/issue/TES-18) differed between direct DNS and a Cloudflare-facing IP. The owners selected Cloudflare Spectrum in PR 4. Pablo then placed Spectrum implementation and validation at the end of the functional product work, before public opening. This is the current sequence.

| Stage | Required path and evidence |
| --- | --- |
| Foundation and functional invited beta | Use a controlled operator or test-player path and record the actual access and exposure. Spectrum does not block profile selection, lifecycle, API, queue or recovery work. |
| Final gate before public opening | Configure Spectrum for Minecraft TCP, validate the edge address and origin restriction, and measure traffic and cost. An authenticated external client must connect, explore, interact, save, restart and reconnect through the stable hostname. Record latency, stalls and gameplay observations. |

TES-18 stays open for that final gate after invited-beta acceptance. Synthetic clients and operator access establish no Spectrum result. HTTP Worker, Access and Tunnel work retains its own managed-service scope.

## Open source license, resolved 2026-09-06

| Decision | Reason and consequence |
| --- | --- |
| License the repository under MIT | Pablo and Agustín Pedernera agreed a permissive license favoring reuse and third-party installation over restricting competing hosting offers. See [LICENSE](../LICENSE). Publication still requires a reproducible two-host foundation, its instructions and evidence, plus the third-party code and asset review and operational-identifier sanitization tracked in [TES-138](https://linear.app/workspace/issue/TES-138). |

## Open decisions

| Decision | What must be recorded before proceeding |
| --- | --- |
| First curated Deploy workload and runtime | A specific application, operating policy, isolation requirements and qualification plan. No sandbox technology is selected in advance. |

A decision changes when its owner records the replacement and why. Update this file and the affected configuration or architecture in the same change. Preserve the earlier evidence and date; do not rewrite a failed experiment as a passing result.
