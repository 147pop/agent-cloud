# Minecraft Java with Vanilla

Status: `Experimental`, historical reference.

| Record | Source |
| --- | --- |
| Recipe | [Base Compose](../../../../benchmarks/minecraft/compose.yml) plus [Vanilla override](../../../../benchmarks/minecraft/compose.vanilla.yml) |
| Version and settings | [Aternos reference interpretation](../../../../benchmarks/minecraft/aternos-reference.md), Mojang 1.20.1, Java 17, 2400 MiB heap |
| Historical Oracle profile | [profile.vanilla.json](../../../../benchmarks/minecraft/profile.vanilla.json), 3 CPU cores, 3200 MiB container limit |
| Result and limits | [Minecraft benchmark](../../../../benchmarks/minecraft/README.md#results) |

All eight synthetic runs completed their actions and persistence checks. Counts of one, two and four bots passed the historical performance rules in both repetitions. Eight bots did not. The test used local operator bots in creative mode; it did not establish Internet-player experience or capacity across simultaneous servers.

The recipe uses offline authentication and binds Minecraft to loopback. It is test material, not a template for a public server. Its 2400 MiB heap is a documented local interpretation of Aternos' published 2400 MB example. Aternos' private host and JVM configuration were not reproduced.

Vanilla is intended for a future paid offer. This profile remains a baseline for experiments. It does not select Vanilla for the free tier or qualify a paid capacity limit.
