# Cloud

Minecraft Java hosting, closed beta preparation.

Start with [E0 in Linear](https://linear.app/workspace/issue/TES-8) for results and pending work. [TES-24](https://linear.app/workspace/issue/TES-24) tracks the server-software comparison; [TES-56](https://linear.app/workspace/issue/TES-56) records the tested player limit.

## Repository

| Directory | Contents |
| --- | --- |
| [infra/inventory](infra/inventory/README.md) | SSH instructions and dated host records |
| [infra/benchmark](infra/benchmark/README.md) | Test commands, pinned recipes, profiles and raw evidence |
| [infra/paper](infra/paper/) | Original Paper Compose recipe |
| [analysis](analysis/) | Earlier product and technical planning |
| [technical](technical/) | Earlier technical reference material |
| [landing](landing/) | Landing-page prototype |

The planning and prototype directories predate E0. They do not describe a deployed Cloud service.

## Where updates belong

Keep executable configuration, operational instructions and measurement files here. Keep conclusions, decisions, task status and next steps in [Linear](https://linear.app/workspace/issue/TES-8), linking the evidence used. Do not copy a results report into both places.

Private keys, environment files and world archives stay outside Git.
