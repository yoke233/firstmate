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

Use this as a Windows adaptation layer, not as a complete firstmate replacement yet.
