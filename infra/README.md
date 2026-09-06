# Infrastructure

Cloud's selected beta design uses one control host, one game worker and a temporary second game worker for recovery tests. The control service is planned. [k3s/](k3s/) installs the cluster itself (TES-59, TES-25).

Read the [architecture](../docs/architecture.md) before adding reusable infrastructure configuration. Put server recipes in the [catalog](../catalog/README.md) and measurement code with the [benchmarks](../benchmarks/README.md).

The dated host inventory, SSH destinations, firewall records and provider identifiers are preserved in the private operator archive attached to [TES-53](https://linear.app/workspace/issue/TES-53). Private keys remain outside Git and Linear. Verify live host state before operating a server.

Historical Git commits and raw E0 measurements still contain operational identifiers. The [public release review](https://linear.app/workspace/issue/TES-138) must resolve their publication before the repository changes visibility.
