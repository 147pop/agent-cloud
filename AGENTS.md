# Repository Agent Instructions

## Sources of truth

- Linear is the source of truth for delivery status, ownership, dependencies and acceptance criteria.
- GitHub is the source of truth for code review, commits, pull requests and published technical evidence.
- Before changing code, read the exact Linear issue and its parent, blockers and blocked issues. Do not infer acceptance criteria from the title alone.
- Keep secrets, host access details, private credentials and sensitive operational evidence out of Git and public pull requests.

## Linear workflow

- Use `Backlog` or `Todo` for work that has not started.
- Move a concrete implementation task to `In Progress` only when work begins. Keep its parent feature in `In Progress` while any required child task or acceptance gate remains open.
- Record the implementation commits and exact verification results in the Linear task before requesting review.
- Move a code task to `In Review` when its pull request is open, conflict-free and ready for review.
- Move a code task to `Done` only after its pull request is merged. A non-code task may move directly to `Done` only when its stated evidence exists.
- Do not close a parent feature merely because one child pull request merged. Check every child, blocker and acceptance criterion first.

## Branches and pull requests

- Use one implementation task per branch and pull request. Start from the latest `origin/main` and include the Linear identifier in the branch name, pull request title and description.
- Do not add work for the next Linear task to a branch with an open pull request. After merge, update `main` and create a fresh branch. Use a stacked pull request only when the user explicitly chooses that workflow.
- Keep each pull request limited to the issue's acceptance criteria. Link the Linear task and list the verification commands and results.
- Request review before merge. Resolve conflicts against the current `main`, rerun the affected checks and update the evidence.
- Prefer a merge commit when the branch contains intentional, focused commits or authorship that should be preserved. Squash only when the user requests it or the intermediate commits have no lasting value.
- Never merge, force-push, delete a branch or discard work without the user's explicit authorization.

## Verification and handoff

- For root TypeScript changes, run `npm run check`.
- When a change could affect existing Minecraft benchmark tooling, also run `python3 benchmarks/minecraft/summarize.py --self-test` and verify that `benchmarks/minecraft/package.json` and its lockfile remain unchanged unless the issue requires otherwise.
- Before reporting completion, verify the worktree is clean, inspect the final diff and confirm the pull request is mergeable.
- After merge, move the Linear task to `Done`, leave a comment with the merged pull request and commit, update the parent task accurately and prepare the next task on a new branch.
