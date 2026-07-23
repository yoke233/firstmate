# firstmate PowerShell MVP

This directory is a Windows-native experiment.
It keeps the firstmate idea but replaces the bash/tmux toolbelt with PowerShell scripts.
The default backend is Orca, with psmux still available as a fallback.

It is intentionally smaller than the upstream `bin/*.sh` implementation:

- `fm-session-start.ps1` initializes local state and prints a compact digest.
- `fm-spawn.ps1` creates an isolated git worktree, a task endpoint, task metadata, and an optional agent launch.
- `fm-peek.ps1` captures a task pane.
- `fm-send.ps1` sends text or keys to a task pane.
- `fm-teardown.ps1` removes a scout task or force-removes a reviewed ship task.

The Windows lifecycle stops safely when a task id is not path-safe, a selector has no durable task record, a configured backend is unsupported, or endpoint cleanup fails.
Spawn refuses to overwrite existing task records and removes resources created by a partially failed spawn when possible.

Use this as a Windows adaptation layer, not as a complete firstmate replacement yet.

## Agent startup

When Codex or another coding agent opens this checkout on Windows, it should follow the Windows override at the top of `AGENTS.md` and run:

```powershell
pwsh -NoLogo -NoProfile -File .\pwsh\fm-session-start.ps1
```

If the agent starts with `bin/fm-session-start.sh`, it is following stale upstream Unix instructions.
Pull the latest branch and restart the agent session so it rereads `AGENTS.md`.
