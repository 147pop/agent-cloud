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
| Publish the code before supporting third-party installation | Public readers must be able to inspect the design, contribution history and evidence. A complete installer is a later delivery. |
| Make GitHub understandable without Linear | Technical decisions and published results have a public home. Linear links to those records and tracks execution. |

## Selected beta design

The 2026-09-03 design narrowed the original plan. The [architecture](architecture.md) carries forward these choices.

| Selected | Previous design | Why |
| --- | --- | --- |
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

These are acceptance rules, not completed test results. [D9's authorizations and incident ownership](https://linear.app/workspace/issue/TES-23) remain in the private project record. D5 is still open below.

## Open decisions

| Decision | What must be recorded before proceeding |
| --- | --- |
| D5, public game TCP and worker IP exposure | One accepted routing policy, tested from an external Minecraft client, with the protection boundary and cost identified. Earlier comments conflict; a closed issue alone does not resolve them. |
| Free Minecraft profile | Comparable engine results, a human play review, concurrent instance measurements and the chosen margin for the host. The older single-instance reference is insufficient. |
| Open source license | The maintainers' chosen license and any required treatment of third-party code or assets. No license is selected in this revision. |
| First curated Deploy workload and runtime | A specific application, operating policy, isolation requirements and qualification plan. No sandbox technology is selected in advance. |

A decision changes when its owner records the replacement and why. Update this file and the affected configuration or architecture in the same change. Preserve the earlier evidence and date; do not rewrite a failed experiment as a passing result.
