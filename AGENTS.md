# Agent Instructions

## Start a Minecraft server (read this first)

When a person asks for a Minecraft server, go straight to a playable endpoint. Do not explore the repository first; everything you need is here.

1. The only question you must ask is whether they accept the Minecraft EULA (https://aka.ms/MinecraftEULA), and only when `.env` does not exist yet. Never assume acceptance. Every other choice has a default: name `minecraft`, loopback address, port 25565, one server per installation.
2. Run `bash infra/compose/up.sh --accept-eula` (omit `--accept-eula` when `.env` exists). It needs only Docker, is safe to rerun, and ends with `READY`, `server_id=` and `endpoint=host:port`. `READY` means the server is already running and passed a Minecraft handshake: do not call start or status afterwards. Intermediate setup lines such as "game-1 exists stopped" are normal. A cold start takes about a minute; a rerun on a running server takes seconds.
3. Give the person the endpoint to paste into Minecraft Java Edition (Multiplayer → Direct Connection), and tell them `bash infra/compose/shutdown.sh` stops everything safely while keeping the world.

After that, manage the same server with the MCP tools of the `agent-cloud` server (`minecraft_status`, `minecraft_stop`, `minecraft_start`; every mutation needs a new `client_request_id`) when your client has them, or with the CLI, which needs no Node.js or token export:

```sh
bash infra/compose/cloud.sh status <server_id>
bash infra/compose/cloud.sh stop <server_id> --wait
bash infra/compose/cloud.sh start <server_id> --wait
```

Handle these results without asking:

| Result | Meaning and action |
| --- | --- |
| `409 capacity_unavailable` | One server already exists and the limit is one. Use that server; never destroy it to make room. |
| `409 action_required: accept_eula` | Ask for EULA acceptance, then retry with it. |
| `507 insufficient_storage` | The disk is short of space. Tell the person how much is free; nothing was changed. |
| `control_unreachable` or a failed `up.sh` | Report the printed log lines; check that Docker is running. |

Never print or commit `.env`, and never run `infra/compose/destroy.sh` or remove volumes unless the person explicitly asks to delete their world. The full reference is [infra/compose/README.md](infra/compose/README.md).

MCP setup: Claude Code reads `.mcp.json` after the person approves the `agent-cloud` server once (the token comes from `.env` through `infra/compose/mcp-headers.sh`). Codex needs `codex mcp add agent-cloud --url http://127.0.0.1:3000/mcp --bearer-token-env-var CLOUD_MACHINE_TOKEN` once and the token exported before launch (`set -a; . ./.env; set +a`). The MCP endpoint exists only while the stack runs; if your session started before `up.sh`, the tools are missing, so use the CLI instead of asking the person to restart.

## Maintainer workflow

### Sources of truth

- Linear is the source of truth for delivery status, ownership, dependencies and acceptance criteria.
- GitHub is the source of truth for code review, commits, pull requests and published technical evidence.
- Before changing code, read the exact Linear issue and its parent, blockers and blocked issues. Do not infer acceptance criteria from the title alone.
- Keep secrets, host access details, private credentials and sensitive operational evidence out of Git and public pull requests.

### Linear workflow

- Use `Backlog` or `Todo` for work that has not started.
- Move a concrete implementation task to `In Progress` only when work begins. Keep its parent feature in `In Progress` while any required child task or acceptance gate remains open.
- Record the implementation commits and exact verification results in the Linear task before requesting review.
- Move a code task to `In Review` when its pull request is open, conflict-free and ready for review.
- Move a code task to `Done` only after its pull request is merged. A non-code task may move directly to `Done` only when its stated evidence exists.
- Do not close a parent feature merely because one child pull request merged. Check every child, blocker and acceptance criterion first.

### Branches and pull requests

- Use one implementation task per branch and pull request. Start from the latest `origin/main` and include the Linear identifier in the branch name, pull request title and description.
- Do not add work for the next Linear task to a branch with an open pull request. After merge, update `main` and create a fresh branch. Use a stacked pull request only when the user explicitly chooses that workflow.
- Keep each pull request limited to the issue's acceptance criteria. Link the Linear task and list the verification commands and results.
- Request review before merge. Resolve conflicts against the current `main`, rerun the affected checks and update the evidence.
- Prefer a merge commit when the branch contains intentional, focused commits or authorship that should be preserved. Squash only when the user requests it or the intermediate commits have no lasting value.
- Never merge, force-push, delete a branch or discard work without the user's explicit authorization.

### Verification and handoff

- For root TypeScript changes, run `npm run check`.
- When a change could affect existing Minecraft benchmark tooling, also run `python3 benchmarks/minecraft/summarize.py --self-test` and verify that `benchmarks/minecraft/package.json` and its lockfile remain unchanged unless the issue requires otherwise.
- Before reporting completion, verify the worktree is clean, inspect the final diff and confirm the pull request is mergeable.
- After merge, move the Linear task to `Done`, leave a comment with the merged pull request and commit, update the parent task accurately and prepare the next task on a new branch.
