# Minecraft Java with Fabric

Status: `Experimental`.

The [free-profile comparison](../../../../benchmarks/minecraft/free-profile-results.md) tested Minecraft 26.2 with Fabric loader 0.19.5, launcher 1.1.2, Lithium 0.25.3 and FerriteCore 9.0.0. The [profile](../../../../benchmarks/minecraft/free-profile.json) pins versions, hashes and resource limits; [compose.free.yml](../../../../benchmarks/minecraft/compose.free.yml) contains the test recipe.

Two nearby synthetic players passed both repetitions with fresh and populated worlds, verified block and movement actions, clean backup/restore and recovery of 32 persistent entities. The [raw evidence](../../../../benchmarks/minecraft/evidence/free/compare-fabric-v2/summary.json) records the actual JAR hashes and configuration. The [measurement report](../../../../benchmarks/minecraft/evidence/free/compare-fabric-v2/measurements.json) explains the result.

The mods run on the server. The [Lithium project](https://github.com/CaffeineMC/lithium) aims to preserve Vanilla mechanics while optimizing server logic. [FerriteCore](https://modrinth.com/mod/ferrite-core) reduces memory structures. The synthetic clients connected without Fabric client mods. An authenticated external game client has not validated this recipe.

Fabric remains an alternative to the current Paper candidate. C2ME is pinned as a conditional variant and has not been tested. No concurrent-instance capacity or public offer is qualified by the nearby-player comparison.

The recipe binds its game port to loopback and uses offline operator identities for the benchmark. Persistent worlds live in the chosen test data directory. Backups, restoration and startup follow the [qualification method](../../../../benchmarks/minecraft/free-profile.md). Version changes and mod additions need their own compatibility and recovery checks before inheriting any result.
