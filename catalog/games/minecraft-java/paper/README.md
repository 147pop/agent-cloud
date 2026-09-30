# Minecraft Java with Paper

Status: `Qualified` for E1. Pablo accepted the repeated bot workload and local recovery checks on 2026-09-06. The limit is one active instance with two players on the tested Oracle A1 host. Public availability and K3s lifecycle acceptance remain pending.

| Record | Source |
| --- | --- |
| Accepted free profile | [free-profile.json](../../../../benchmarks/minecraft/free-profile.json), Paper 26.2 build 121, 2 CPU quota units, 2 GiB heap, 3 GiB container, view 6, simulation 4 |
| Acceptance evidence | [TPS by activity and recovery results](../../../../benchmarks/minecraft/free-profile-results.md#tps-by-player-activity) |
| Original smoke recipe | [compose.smoke.yml](compose.smoke.yml), Paper 26.2 build 121, pinned image, 4 GiB heap |
| Benchmark recipe | [compose.yml](../../../../benchmarks/minecraft/compose.yml), 3 CPU cores, 4 GiB heap, 5 GiB container limit |
| K3s recipe for E1 | [k8s/](k8s/), accepted game settings, Deployment and PVC, interrupted-stop test runbook |
| Historical Oracle profile | [profile.json](../../../../benchmarks/minecraft/profile.json) |
| Historical result and limits | [Minecraft benchmark](../../../../benchmarks/minecraft/README.md#results) |

The historical Oracle study completed eight synthetic runs. One bot was the only count to pass the historical performance rules in both repetitions. Those rules and the test workload do not establish capacity for ordinary multiplayer sessions.

`compose.smoke.yml` preserves the initial loopback-only recipe. Its `./data` bind mount resolves beside that file when it is the Compose project directory. Moving the file did not move or change any existing server world. The smoke recipe has no CPU or container-memory cap and no capacity qualification.

The benchmark recipe uses offline operator bots, creative mode and private RCON. Both recipes are test material. Neither is a template for a public server.

The [controlled free comparison](../../../../benchmarks/minecraft/free-profile-results.md) uses Minecraft 26.2 build 121, two CPU quota units, a 2 GiB heap, a 3 GiB container limit and native tick percentiles. Its [recipe and profile](../../../../benchmarks/minecraft/free-profile.md) are separate from the older study. Two nearby synthetic players passed both repetitions, including populated worlds and clean backup/restore.

Paper also passed two repetitions with player routes 256 blocks apart. The longer density workload passed twice with one instance and two players. Two instances failed the RCON response cut during a save; this does not establish the host's physical maximum. The [profile](../../../../benchmarks/minecraft/free-profile.json) records the owner's acceptance of the synthetic result and its E1 scope. No gameplay plugins were added to the comparison. Spectrum implementation and authenticated external play are final public-opening checks in TES-18.

## Gameplay differences

The [recorded Spigot configuration](../../../../benchmarks/minecraft/evidence/free/compare-paper/r1-i1-config/spigot.yml) uses 32-block activation ranges for animals, monsters and villagers, and 16 blocks for miscellaneous entities and water mobs. Entities outside their activation range tick less frequently. This can affect farms and item movement. See the [Paper configuration reference](https://docs.papermc.io/paper/reference/spigot-configuration/).

The [recorded global configuration](../../../../benchmarks/minecraft/evidence/free/compare-paper/r1-i1-config/paper-global.yml) leaves piston duplication, headless pistons and permanent-block-breaking exploits disabled. This includes the documented TNT, carpet and rail duplication exploits. The [Paper reference](https://docs.papermc.io/paper/reference/global-configuration/) describes those switches.

These are documented settings and expected effects. The benchmark did not test technical farms or duplication machines. The [Paper Vanilla guide](https://docs.papermc.io/paper/vanilla/) also explains why Paper cannot reproduce every Vanilla behavior. The external session before public opening will record issues observed during ordinary play.
