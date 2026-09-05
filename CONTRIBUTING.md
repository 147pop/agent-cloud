# Contributing

Cloud is in pre-beta development. Start with the [repository overview](README.md), [architecture](docs/architecture.md) and [catalog requirements](catalog/README.md). The current executable work is the benchmark tooling and Minecraft recipes. There is no complete platform installer yet.

## Choose a change

Use [GitHub issues](https://github.com/pjcdz/cloud/issues) for public bug reports and proposals. Maintainers use Linear for delivery planning. A contributor should not need Linear access to understand a GitHub issue or pull request.

A change should name the result it produces and the evidence that will demonstrate it. Keep unrelated changes separate. Link the Linear task when one exists, but include the problem and acceptance criteria in the public description.

## Work locally

Create a branch from the current `main`. Preserve other contributors' commits and unfinished work. Follow the commands in the component README rather than assuming a shared VPS or local credential is available.

The benchmark summary includes a local check that does not contact a host:

```sh
python3 benchmarks/minecraft/summarize.py --self-test
```

For actual Minecraft runs, use the [benchmark guide](benchmarks/minecraft/README.md). Provisioning, network probes and load tests require an explicitly selected test environment. A parser check cannot establish a server's playing quality or capacity.

There is no root application build to run. Documentation changes need working links and instructions checked against the files they describe. Runtime changes need the smallest check that fails when the intended behavior breaks.

## Submit evidence with the change

The pull request should explain the behavior before and after the change, list the checks run and link their evidence. Include the commit, pinned versions, workload, resource limits and observed result for a benchmark claim. Record incomplete and failed runs with their limits.

Keep the summary beside its raw evidence. Link a commit when a result must remain reproducible; link `main` for current instructions. Update the [decision record](docs/decisions.md) when a change replaces a technical choice.

Keep credentials, environment files, access instructions for private hosts, personal data and world archives outside Git. Review generated logs before adding them. Redacted evidence must say what was removed and must not retain checksums that claim to cover the pre-redaction bytes.

Preserve commit authorship when integrating work. Describe contributions in the pull request when commits alone do not capture them. Maintainers record the accepted result in Linear after the relevant checks pass; merging code does not by itself complete an operational acceptance test.

## Code publication

The repository does not yet contain an open source license. The maintainers must settle licensing and review third-party code and assets before publishing the code. Third-party installation and a supported deployment release are separate later work.

Follow [SECURITY.md](SECURITY.md) for sensitive reports.
