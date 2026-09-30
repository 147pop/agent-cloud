# Security

Agent Cloud is in pre-beta development. The supported release is the single-host [Docker Compose foundation](infra/compose/README.md); there is no managed production service yet. The [architecture](docs/architecture.md#trust-boundaries) describes intended controls; it does not certify a deployed service.

## Report a vulnerability

Report vulnerabilities privately through [GitHub private vulnerability reporting](https://github.com/147pop/agent-cloud/security/advisories/new). Only the maintainers can see the report. Include the affected commit, component, expected behavior, observed behavior and a minimal reproduction with synthetic data.

Do not put credentials, tenant data, exploit details or private infrastructure details in a public issue, pull request, benchmark artifact or screenshot.

For a non-sensitive concern, open a [GitHub issue](https://github.com/147pop/agent-cloud/issues).

## Supported versions

Only the current `main` branch receives fixes.
