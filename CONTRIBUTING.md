# Contributing

Cloud is in pre-beta development. Start with the [repository overview](README.md), [architecture](docs/architecture.md) and [catalog requirements](catalog/README.md). The current executable work is the benchmark tooling, K3s installer and Minecraft runtime manifests. There is no root `cloud-control` application or complete two-host deployment yet.

## Choose a change

Use [GitHub issues](https://github.com/pjcdz/cloud/issues) for public bug reports and proposals. Maintainers use Linear for delivery planning. A contributor should not need Linear access to understand a GitHub issue or pull request.

A change should name the result it produces and the evidence that will demonstrate it. Keep unrelated changes separate. Link the Linear task when one exists, but include the problem and acceptance criteria in the public description.

## Work locally

Create a branch from the current `main`. Preserve other contributors' commits and unfinished work. Follow the commands in the component README rather than assuming a shared VPS or local credential is available. Use only hosts and credentials that you control.

The benchmark summary includes a local check that does not contact a host:

```sh
python3 benchmarks/minecraft/summarize.py --self-test
```

For actual Minecraft runs, use the [benchmark guide](benchmarks/minecraft/README.md). Provisioning, network probes and load tests require an explicitly selected test environment. A parser check cannot establish a server's playing quality or capacity.

There is no root application build to run yet. Documentation changes need working links and instructions checked against the files they describe. Runtime changes need the smallest check that fails when the intended behavior breaks.

The first runtime target is K3s on two compatible hosts. Local containers, mocks and other development tools may shorten feedback, but they do not establish the two-host acceptance result or gate publication when the real deployment passes.

## Submit evidence with the change

The pull request should explain the behavior before and after the change, list the checks run and link their evidence. Include the commit, pinned versions, workload, resource limits and observed result for a benchmark claim. Record incomplete and failed runs with their limits.

Foundation evidence must start from a clean clone and record the two host roles, compatible host properties, deployment commands and operator-owned credential setup. It must exercise one complete agent request through create, start, status and stop. The result must include a playable endpoint after protocol readiness, world persistence, ownership checks and durable `client_request_id` behavior across a `cloud-control` restart. Prove cold start and assignment of a ready unowned warm instance in separate trials if the selected capacity cannot run both. Record bounded capacity and the direct network path used for player TCP.

Keep the summary beside its raw evidence. Link a commit when a result must remain reproducible; link `main` for current instructions. Update the [decision record](docs/decisions.md) when a change replaces a technical choice.

Keep credentials, environment files, access instructions for private hosts, personal data and world archives outside Git. Review generated logs before adding them. Redacted evidence must say what was removed and must not retain checksums that claim to cover the pre-redaction bytes.

Preserve commit authorship when integrating work. Describe contributions in the pull request when commits alone do not capture them. Maintainers record the accepted result in Linear after the relevant checks pass; merging code does not by itself complete an operational acceptance test.

## Code publication

The repository is licensed under [MIT](LICENSE). Before publication, the maintainers must reproduce the bounded foundation from a clean clone on two compatible hosts using the repository instructions and their own credentials. They must publish the code, instructions and evidence together. They must also review third-party code and assets and sanitize operational identifiers retained in Git history.

This publication requirement covers the two-host foundation. Public registration, billing, managed Cloudflare routing, public operating scale and remote disaster recovery belong to the later managed service.

Follow [SECURITY.md](SECURITY.md) for sensitive reports.
