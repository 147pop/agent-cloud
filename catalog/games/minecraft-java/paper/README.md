# Minecraft Java with Paper

Status: `Experimental`.

| Record | Source |
| --- | --- |
| Original smoke recipe | [compose.smoke.yml](compose.smoke.yml), Paper 26.2 build 121, pinned image, 4 GiB heap |
| Benchmark recipe | [compose.yml](../../../../benchmarks/minecraft/compose.yml), 3 CPU cores, 4 GiB heap, 5 GiB container limit |
| Historical Oracle profile | [profile.json](../../../../benchmarks/minecraft/profile.json) |
| Result and limits | [Minecraft benchmark](../../../../benchmarks/minecraft/README.md#results) |

The Oracle study completed eight synthetic runs. One bot was the only count to pass the historical performance rules in both repetitions. Those rules and the test workload do not establish capacity for ordinary multiplayer sessions.

`compose.smoke.yml` preserves the initial loopback-only recipe. Its `./data` bind mount resolves beside that file when it is the Compose project directory. Moving the file did not move or change any existing server world. The smoke recipe has no CPU or container-memory cap and no capacity qualification.

The benchmark recipe uses offline operator bots, creative mode and private RCON. Both recipes are test material. Neither is a template for a public server.

Paper remains a candidate for the optimized free tier. Selecting a current engine, version and profile requires the [controlled comparison and shared-host tests](../../../../benchmarks/minecraft/README.md#qualifying-a-free-profile). No optimized free offer has been selected from this historical result.
