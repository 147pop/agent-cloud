# Benchmarks

Measured results belong here. The [catalog](../catalog/README.md) links recipes and profiles to their evidence. Linear tracks the work needed to qualify an offer.

| Question | Record |
| --- | --- |
| What has Minecraft demonstrated? | [Results, limits and reproduction](minecraft/README.md) |
| How were the two initial hosts measured? | [Disk](minecraft/README.md#disk), [network](minecraft/README.md#network) and [firewall probes](minecraft/README.md#firewall-probes) |
| What is still needed for the free tier? | [Candidate comparison and shared-host qualification](minecraft/README.md#qualifying-a-free-profile) |

The current files come from the E0 Minecraft study. Its infrastructure probes stay with the original suite because `network.py` imports the application guard from `run.py`. The evidence and source hashes retain their original relative paths. No new benchmark ran during the directory move.

Each future run must identify the recipe, versions, host hardware, resource limits, workload, acceptance rules and source commit. Keep the raw observations beside the derived result, including failed attempts. A successful start proves that the recipe starts. An offer needs evidence for the usage and resource limits it promises.
