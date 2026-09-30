# Contributing

Agent Cloud is in pre-beta development. Start with the [repository overview](README.md), [architecture](docs/architecture.md) and [catalog requirements](catalog/README.md). The supported executable work is the TypeScript `cloud-control` application, the [single-host Docker Compose installation](infra/compose/README.md) and the benchmark tooling. The two-host K3s installation is retained as historical evidence.

## Choose a change

Use [GitHub issues](https://github.com/147pop/agent-cloud/issues) for public bug reports and proposals. Maintainers plan delivery in a private tracker; `TES-…` identifiers in the records refer to it. A contributor never needs tracker access to understand a GitHub issue or pull request.

A change should name the result it produces and the evidence that will demonstrate it. Keep unrelated changes separate. Include the problem and acceptance criteria in the public description.

## Work locally

Create a branch from the current `main`. Preserve other contributors' commits and unfinished work. Follow the commands in the component README rather than assuming a shared VPS or local credential is available. Use only hosts and credentials that you control.

The benchmark summary includes a local check that does not contact a host:

```sh
python3 benchmarks/minecraft/summarize.py --self-test
```

For actual Minecraft runs, use the [benchmark guide](benchmarks/minecraft/README.md). Provisioning, network probes and load tests require an explicitly selected test environment. A parser check cannot establish a server's playing quality or capacity.

Install the pinned root toolchain with `npm ci` and run the TypeScript application checks with `npm run check`. Changes to the Compose runtime also need `bash infra/compose/test.sh` and, for lifecycle behavior, `bash infra/compose/journey.sh --accept-eula` on a machine you control. Documentation changes need working links and instructions checked against the files they describe. Runtime changes need the smallest check that fails when the intended behavior breaks.

For control database changes, set `TEST_DATABASE_URL` to a disposable PostgreSQL database and run `npm run test:integration`. The test creates and removes its own schema. It checks actual database constraints, machine authentication and durable records across a new control store. It does not establish two-host acceptance.

The supported runtime is Docker Compose on one host. Mocks and focused tests shorten feedback, but lifecycle acceptance requires a real Compose run from a clean clone.

## Submit evidence with the change

The pull request should explain the behavior before and after the change, list the checks run and link their evidence. Include the commit, pinned versions, workload, resource limits and observed result for a benchmark claim. Record incomplete and failed runs with their limits.

Foundation evidence must start from a clean clone and record the commit, OS, architecture, Docker and Compose versions, commands and operator-owned credential setup. It must exercise one complete agent request through create, status, stop and start, with a playable endpoint only after protocol readiness, world persistence, ownership checks and durable `client_request_id` behavior across a `cloud-control` restart. See the [journey](infra/evidence/tes-155-agent-to-play-journey.md) and [trials](infra/evidence/tes-156-persistence-idempotency-restart.md) evidence for the expected shape.

Keep the summary beside its raw evidence. Link a commit when a result must remain reproducible; link `main` for current instructions. Update the [decision record](docs/decisions.md) when a change replaces a technical choice.

Keep credentials, environment files, access instructions for private hosts, personal data and world archives outside Git. Review generated logs before adding them. Redacted evidence must say what was removed and must not retain checksums that claim to cover the pre-redaction bytes.

Preserve commit authorship when integrating work. Describe contributions in the pull request when commits alone do not capture them. Merging code does not by itself complete an operational acceptance test.

## Code publication

The repository is licensed under [MIT](LICENSE). The single-host Compose foundation was published after a clean-clone reproduction, a third-party code and asset review and a sanitization of operational identifiers in Git history; see the [public release record](infra/evidence/tes-139-public-release.md). Public registration, billing, managed routing, public operating scale and remote disaster recovery belong to the later managed service.

Follow [SECURITY.md](SECURITY.md) for sensitive reports.
