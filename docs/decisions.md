# Decisions

This file records the current direction without requiring access to the planning system. Implementation evidence belongs with the component or benchmark that produced it. Work assignments and discussion belong in Linear.

## Local-first delivery, 2026-09-06

The owners changed the delivery sequence after reviewing the gap between the runnable repository and the managed-service roadmap.

| Decision | Reason and consequence |
| --- | --- |
| Accept a complete local product first | A clean clone must run PostgreSQL, `cloud-control` and one persistent Minecraft server, then complete `create → start → status → connect → stop` without cloud credentials. |
| Keep the control plane runtime-neutral | Core state, operations, idempotency and reconciliation must not depend on Docker or Kubernetes types. Docker is the first adapter; Kubernetes follows for the managed service. |
| Run the local stack through Compose and the Docker socket | `docker compose up --build` starts PostgreSQL and a containerized `cloud-control`; the control container manages sibling Minecraft containers through `/var/run/docker.sock`. Every exposed port stays on loopback, and this development-only privilege is forbidden in managed mode. |
| Use an explicit local development identity | `CLOUD_MODE=local` bootstraps one principal. `CLOUD_DEV_TOKEN` defaults to the non-secret `local-dev-token` only on loopback; managed mode rejects that default and never bootstraps the local account. |
| Develop Docker and interfaces in parallel after the core | L2 and L3 both depend on L1. L4 integrates and accepts them together instead of serializing all interface work behind the Docker adapter. |
| Use one cross-platform acceptance suite | Linux CI is the continuous gate. The same automated suite is run and recorded on Docker Desktop for macOS until a maintained macOS Docker runner exists. |
| Gate publication and managed adaptation on local acceptance | Source publication must include a reproducible local journey. The managed beta reuses that accepted core instead of creating a parallel implementation. |
| Keep production self-hosting separate | Local development is not a promise to operate Cloud safely on arbitrary third-party infrastructure. Packaging and support for that use remain later work. |

## Product direction, 2026-09-05

The product owner settled these choices while revising the Cloud organization plan.

| Decision | Reason and consequence |
| --- | --- |
| Keep Host and Deploy in the product | Minecraft is the first delivery. Games and curated applications remain visible in the roadmap without implying that they are implemented. |
| Exclude Continue for now | Agent-hosting environments are outside the current product work. Using an agent as a Cloud client remains in scope. |
| Optimize the free Minecraft offer for efficiency | A familiar game experience with documented differences is acceptable. Compare optimized engines and measure concurrent server density before choosing the default. |
| Place official Vanilla in the later paid catalog | Strict Vanilla behavior may require a different resource profile. Payment does not remove its qualification requirements. |
| Start Deploy with a curated catalog | The team can define and test how each application starts, persists and recovers. Arbitrary images and repositories require a later isolation design. |
| Publish after the repository works locally, before supporting third-party production installation | Public readers must be able to inspect and run the accepted local journey. A production installer and operating support remain later deliveries. This sequence supersedes publication of a documentation-only repository. |
| Make GitHub understandable without Linear | Technical decisions and published results have a public home. Linear links to those records and tracks execution. |

## Selected beta design

The 2026-09-03 design narrowed the original plan. The [architecture](architecture.md) carries forward these choices.

| Selected | Previous design | Why |
| --- | --- | --- |
| Runtime-neutral `cloud-control` core with parallel Docker and interface work, followed by a Kubernetes adapter | Kubernetes embedded directly in reconciliation | The complete product flow can be developed and accepted locally before managed infrastructure is required without serializing interface development behind Docker. |
| One TypeScript `cloud-control` process with PostgreSQL | Retained from the original plan | The first account, queue and lifecycle flow can share one process and durable database state. |
| Deployment with zero or one replicas and an explicit PVC | StatefulSet wording in the original plan | The first workload needs one process and a persistent directory. Stop and recovery tests must still establish one active writer. |
| Local PVC plus R2 backup and operated recovery | Longhorn required before a second worker | Measure restore time and lost progress before adding replicated storage. |
| Polling for queue and status | Server-Sent Events in the original plan | The beta needs durable state and a usable status page; its traffic has not justified another transport. |
| Codex as the first acceptance client | Simultaneous support claims for several clients | Each client needs its own verified create-to-play flow. |
| A free invited beta before billing | Payment behavior included in the first product path | Establish persistence, recovery, usage and costs before charging for them. |

Git history preserves earlier designs. In particular, the previous Docker Sandboxes and Continue plan does not prescribe Deploy's runtime.

## Invited beta rules, 2026-09-04

Agustín Pedernera recorded these approvals in the decision issues. The later bilingual update replaces the original Spanish-only audience description.

| Decision | Accepted rule |
| --- | --- |
| [D1, scope](https://linear.app/workspace/issue/TES-15) | Account, EULA, MCP token, create, start, status, stop, stable address, queue, confirmation, AutoStop, persistence, automatic backup and operator-run restore. User-selected versions, plugins, console, world import and self-service restore follow later. |
| [D2, audience](https://linear.app/workspace/issue/TES-16) | Known users, English and Spanish, at most 20 accounts, two weeks. |
| [D3, free rules](https://linear.app/workspace/issue/TES-17) | One logical server and one active server per account, 4 GB soft storage threshold, five-minute AutoStop, five-minute turn confirmation and operator-confirmed deletion before replacement. |
| [D4, recovery](https://linear.app/workspace/issue/TES-19) | The protection target is the last clean stop. E4 must measure recovery before any duration is promised. The target does not guarantee preservation of an unfinished session. |
| [D6, client](https://linear.app/workspace/issue/TES-20) | Codex with a revocable bearer token is the first client to qualify through the complete E2 journey. |
| [D7, billing](https://linear.app/workspace/issue/TES-21) | The first beta is free. Billing follows 100 real runs, proven recovery between workers and measured costs. |
| [D8, availability](https://linear.app/workspace/issue/TES-22) | Accept one control host for the invited beta, conditional on restoring it on a clean host and assigning an incident owner before opening the beta. |

These are acceptance rules, not completed test results. [D9's authorizations and incident ownership](https://linear.app/workspace/issue/TES-23) remain in the private project record.

## Free Paper profile, accepted 2026-09-06

Pablo accepted the repeated bot workload and local recovery evidence for TES-144 and TES-140. This replaces the earlier requirement for a human session before E1 profile selection. The [results](../benchmarks/minecraft/free-profile-results.md#tps-by-player-activity) show active exploration in separate terrain, combat and block actions in two repetitions.

| Decision | Reason and consequence |
| --- | --- |
| Use Paper 26.2 build 121 with the tested free configuration | Two CPU quota units, 2 GiB heap, 3 GiB container, `ActiveProcessorCount=2`, view 6, simulation 4, seed 20260904 and no gameplay plugins. |
| Accept one active instance with two players on the tested Oracle A1 host | Both repetitions passed exploration, combat and local recovery. Two instances failed the control-response threshold during a save. Four or eight players in one instance were not tested with this recipe. |

The profile is Qualified for E1. The [K3s recipe](../catalog/games/minecraft-java/paper/k8s/) uses the accepted game settings; its lifecycle checks, platform backups and recovery remain separate work. This decision does not claim human-client or public-route evidence.

## D5, public game TCP and worker IP exposure, updated 2026-09-06

The earlier comments in [TES-18](https://linear.app/workspace/issue/TES-18) differed between direct DNS and a Cloudflare-facing IP. The owners selected Cloudflare Spectrum in PR 4. Pablo then placed Spectrum implementation and validation at the end of the functional product work, before public opening. This is the current sequence.

| Stage | Required path and evidence |
| --- | --- |
| E1 through the functional invited beta | Use a controlled operator or test-player path and record the actual access and exposure. Spectrum does not block profile selection, lifecycle, API, queue or recovery work. |
| Final gate before public opening | Configure Spectrum for Minecraft TCP, validate the edge address and origin restriction, and measure traffic and cost. An authenticated external client must connect, explore, interact, save, restart and reconnect through the stable hostname. Record latency, stalls and gameplay observations. |

TES-18 stays open for that final gate after invited-beta acceptance. Synthetic clients and operator access establish no Spectrum result. HTTP Worker, Access and Tunnel work retains its own E2 scope.

## Open source license — resolved 2026-09-06

| Decision | Reason and consequence |
| --- | --- |
| License the repository under MIT | Pablo and Agustín Pedernera agreed a permissive license favoring reuse and third-party installation over restricting competing hosting offers. See [LICENSE](../LICENSE). This does not by itself authorize flipping the repository to public: [TES-138](https://linear.app/workspace/issue/TES-138) (third-party code/asset review and sanitizing operational identifiers in Git history) remains open and gates that. |

## Open decisions

| Decision | What must be recorded before proceeding |
| --- | --- |
| First curated Deploy workload and runtime | A specific application, operating policy, isolation requirements and qualification plan. No sandbox technology is selected in advance. |

A decision changes when its owner records the replacement and why. Update this file and the affected configuration or architecture in the same change. Preserve the earlier evidence and date; do not rewrite a failed experiment as a passing result.
