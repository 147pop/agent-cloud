# Workload catalog

Cloud starts with Minecraft and will add other games and curated applications. Paper has an accepted E1 profile. Other entries remain experiments, and no public offer is active.

| Workload | Entry | Current state |
| --- | --- | --- |
| Minecraft Java | [Paper](games/minecraft-java/paper/README.md) | Qualified for E1, one instance with two players, based on owner-accepted bot and local recovery evidence |
| Minecraft Java | [Fabric](games/minecraft-java/fabric/README.md) | Controlled comparison with Lithium and FerriteCore |
| Minecraft Java | [Vanilla](games/minecraft-java/vanilla/README.md) | Historical reference for the low-resource study |

## What an entry contains

| Record | Purpose |
| --- | --- |
| Recipe | Pins the software and explains configuration, ports, start, stop and persistent data |
| Tested profile | Records hardware, resource limits, workload and the versions that were measured |
| Evidence | Identifies the run, raw observations, checks, result and known limits |
| Offer | Defines which tested profile users can choose, its free or paid tier and its usage limits |

Keep configuration in one place. These entries link to the existing benchmark recipes instead of copying them. A profile from one host or game version does not qualify a different host, version or modpack.

## Adding a workload

Add a directory when there is a recipe to inspect. Its README must state its status and link the recipe, supported versions, resource profile and evidence. Record required client software, plugins or mods, configuration differences, persistent paths and the procedure for upgrades and data recovery. Mark anything that has not been tested.

Use these statuses consistently:

- `Experimental`: the recipe or tests are incomplete. No user capacity is promised.
- `Qualified`: the documented profile passed its owner-approved acceptance checks. State the workload, recovery boundary, whether clients were synthetic or human, and what remains untested. The claim applies only to that profile and scope.
- `Offered`: the managed service exposes a qualified profile with explicit support and usage limits.
- `Retired`: the entry remains readable, but new deployments are no longer supported.

A version update or configuration change needs a recorded check before inheriting qualification. Modpack combinations need their own evidence. Installation by contributors and availability in the managed service are separate claims.

## Planned offers

The free Minecraft tier uses the Paper profile accepted on 2026-09-06 for E1, with one active instance and two players on the tested Oracle A1 host. [The qualification results](../benchmarks/minecraft/free-profile-results.md) include repeated exploration on separate routes, combat, local recovery and the failed two-instance level. The owner accepted this evidence for profile selection. K3s lifecycle and platform recovery still require their own acceptance. Human play and the live Spectrum route remain pending before public opening. Gameplay differences from Mojang Vanilla are recorded in the Paper entry.

Vanilla and additional game configurations belong to the future paid catalog. The historical Vanilla result is a reference, not a free-tier commitment. Pricing and capacity remain undecided.

Deploy will start with applications that the maintainers select, test and maintain. Arbitrary user images and repositories come later because they require a broader execution and support model. Agent workloads, previously called Continue, are outside the current plan.
