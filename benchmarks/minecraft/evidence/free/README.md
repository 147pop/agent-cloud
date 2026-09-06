# Free-profile evidence

[The method](../../free-profile.md) records the shortlist, fixed recipe, workload and screening limits. These local synthetic tests do not close external human acceptance or define a public offer.

| Attempt | Result | Use |
| --- | --- | --- |
| [pilot-paper](pilot-paper/summary.json) | Placement failed because the pinned client data used the wrong outgoing packet ID | Client diagnosis only |
| [pilot-paper-v2](pilot-paper-v2/summary.json) | The block check accepted a local client update before server confirmation; a remaining combat mob also interfered | Client diagnosis only |
| [pilot-paper-v3](pilot-paper-v3/summary.json) | Restore produced root-owned world files and restart failed with an access error; the walk check also counted falling as movement | Runner diagnosis only |
| [pilot-paper-v4](pilot-paper-v4/summary.json) | Complete short action, population, backup and restart check | Preparation, too short for capacity |
| [pilot-fabric](pilot-fabric/summary.json) | Complete short action, population, backup and restart check after the chunk loading correction | Preparation, too short for capacity |
| [compare-paper](compare-paper/measurements.json) | Two complete repetitions with two players, fresh and populated worlds; all screening limits passed | Repeated evidence for one instance |
| [compare-fabric-v2](compare-fabric-v2/measurements.json) | Two complete repetitions with two players, fresh and populated worlds; all screening limits passed | Repeated evidence for one instance |
| [compare-fabric](compare-fabric/summary.json) | Fresh-world actions completed; marker preparation failed after Fabric unloaded the disconnected clients' chunk | Incomplete; no accepted capacity |

The early Paper pilots retain logs, metrics and source hashes, but their exact intermediate source files were not archived. Do not describe those debugging attempts as fully reconstructible. Formal attempts beginning with `compare-paper` include `sources.tar.gz`, whose members match the recorded `source_sha256` values.

`summary.json` and the JSONL files retain the original observations, including failures. `measurements.json` is derived with `qualify.py --report` and records that reporter's SHA-256. The reporter requires continuous simultaneous play in each phase and repetition. Its version can differ from the runner archived with an earlier attempt. Fabric launcher snapshots match the original runtime hashes; their entry contents are compared separately because the generated ZIP timestamps differ. The game JAR and other dependencies still require matching raw hashes.

The corrected Fabric runner temporarily loads the four persistence chunks only after players exit, and releases them before backup. It also waits for those chunks before population setup and restart verification. The Paper measurements used the earlier runner, where the chunk was still loaded; both candidates use the same active player script, pinned game versions, configuration and limits.

Worlds and backup archives remain on the authorized host. The export contains source bundles, hashes, configuration, metrics and logs. It excludes `.env`, credentials and world data. Run `shasum -a 256 -c SHA256SUMS` inside an attempt directory to verify the export.
