---
name: update-pwsh-fork
description: >-
  Synchronize this Windows PowerShell fork with GitHub upstream/main, preserve and update pwsh/, resolve merge conflicts, validate, commit, and push safely.
  Use in the firstmate-pwsh checkout whenever the captain says "更新", "更新一下", "拉取上游", "同步 upstream", or asks to update the pwsh/PowerShell fork.
  Do not use for an explicitly requested fast-forward-only update from origin; use updatefirstmate for that.
---

# Update PowerShell Fork

Synchronize upstream shared material while retaining the Windows-native operating layer.
Never force, stash, discard work, run Bash, or merge a PR.

## Preconditions

1. Run the repository's PowerShell session-start command only when it has not already run in the current session.
2. Load `firstmate-coding-guidelines` before changing shared tracked material.
3. Confirm the checkout, current branch, remotes, and `git status --short --branch`.
4. Require a clean tracked worktree before fetching or merging.
5. Stop on local edits, divergence, an unexpected branch, missing upstream, or unresolved work instead of stashing or forcing.

## Synchronize

1. Fetch `upstream` with pruning.
2. Fetch `origin` independently; an origin transport failure must not invalidate a successful upstream fetch.
3. Resolve the upstream default branch from Git rather than assuming it when the remote advertises another default.
4. Record the current commit, upstream commit, merge base, left/right counts, and upstream-only log.
5. If upstream has no new commits, report a no-op and do not create a commit.
6. Merge the upstream default branch with `git merge --no-commit --no-ff`.

## Resolve and port

1. Load `resolving-merge-conflicts` whenever Git reports a conflict.
2. Preserve both the latest upstream shared contracts and the Windows override at the top of `AGENTS.md`.
3. Preserve `pwsh/`, `docs/windows-pwsh-backends.md`, Windows CI coverage, and PowerShell startup routing.
4. Never use a whole-tree ours strategy or accept upstream deletions of the Windows layer without explicit captain approval.
5. Compare upstream changes since the merge base and port only cross-platform behavior that the current PowerShell runtime can support.
6. Prefer safety boundaries, durable state, cleanup integrity, and observable behavior over speculative feature parity.
7. Keep Unix-only watcher, AFK, secondmate, X-mode, and harness mechanisms documented as unported until their Windows runtime exists.

## Validate

1. Add or update observable PowerShell regression tests for changed behavior.
2. Run:

```powershell
pwsh -NoLogo -NoProfile -File .\tests\fm-pwsh.test.ps1
git diff --check
```

3. Confirm no conflict markers remain and every Windows file is present in the proposed tree.
4. For a complex or high-impact update, run an independent adversarial review, verify its cited lines, fix confirmed issues, and rerun tests.
5. Stage the complete merge, ensure no unmerged entries remain, and commit with a terse message without an agent co-author.

## Publish

1. Push the current branch to `origin` without force.
2. If SSH port 22 is blocked, use GitHub's SSH-over-443 endpoint for that invocation without rewriting the saved remote.
3. If HTTPS rejects workflow changes because the OAuth token lacks `workflow` scope, preserve the CI changes and use authenticated SSH-over-443 or ask the captain to refresh credentials.
4. Verify the local commit matches the remote branch after pushing.
5. Do not create or merge a PR unless the captain requested that additional action.
6. Report the upstream commit absorbed, resulting commit, pushed branch, tests run, and any intentionally unported Windows limitations.

Use this PowerShell-only fallback shape for an SSH-over-443 push after deriving the current branch:

```powershell
$branch = git branch --show-current
git -c 'url.ssh://git@ssh.github.com:443/.insteadOf=git@github.com:' `
    -c 'core.sshCommand=ssh -p 443' `
    push origin $branch
```
