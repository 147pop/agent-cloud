# Workload catalog

Cloud starts with Minecraft and will add other games and curated applications. The entries below describe experiments. There is no qualified public offer yet.

| Workload | Entry | Current state |
| --- | --- | --- |
| Minecraft Java | [Paper](games/minecraft-java/paper/README.md) | Repeated synthetic pass for one instance with two players; external acceptance pending |
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
- `Qualified`: the documented profile passed its stated checks, including real use and recovery. The claim applies only to that profile.
- `Offered`: the managed service exposes a qualified profile with explicit support and usage limits.
- `Retired`: the entry remains readable, but new deployments are no longer supported.

A version update or configuration change needs a recorded check before inheriting qualification. Modpack combinations need their own evidence. Installation by contributors and availability in the managed service are separate claims.

## Planned offers

The free Minecraft tier will prioritize the number of acceptable simultaneous sessions per host. An optimized engine may differ from Mojang Vanilla; document those differences and test ordinary play before selecting it. [The qualification results](../benchmarks/minecraft/free-profile-results.md) record Paper's repeated synthetic pass for one instance with two players and the failed two-instance level. Human play and the live Spectrum route remain pending. These results have not qualified a public offer.

Vanilla and additional game configurations belong to the future paid catalog. The historical Vanilla result is a reference, not a free-tier commitment. Pricing and capacity remain undecided.

Deploy will start with applications that the maintainers select, test and maintain. Arbitrary user images and repositories come later because they require a broader execution and support model. Agent workloads, previously called Continue, are outside the current plan.
