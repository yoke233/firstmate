# Windows PowerShell backends

This document describes the experimental Windows-native adaptation in `pwsh/`.

The goal is to preserve firstmate's core operating model while avoiding WSL, MSYS2, bash, and Unix tmux.

## Model

The MVP keeps four firstmate ideas:

- one primary agent talks to the user;
- each task gets a separate git worktree;
- task state is durable on disk under `state/` and `data/`;
- the visible task endpoint is an Orca terminal by default, or a psmux window when selected.

It does not yet port the full bash watcher, no-mistakes integration, secondmates, X mode, or PR lifecycle.

## Requirements

- Windows 10 or Windows 11.
- PowerShell 7+.
- Orca CLI, discovered from `FM_ORCA_CMD`, `config/orca-command`, `PATH`, or `%LOCALAPPDATA%\Programs\Orca\resources\bin\orca.cmd`.
- `psmux` on `PATH` only when using the psmux fallback backend.
- `git`.
- One supported harness on `PATH`, such as `codex` or `claude`.

Install psmux with one of the upstream-supported methods when you want the fallback backend:

```powershell
winget install psmux
```

or:

```powershell
scoop bucket add psmux https://github.com/psmux/scoop-psmux
scoop install psmux
```

psmux is a Windows-native Rust terminal multiplexer that exposes tmux-compatible commands such as `new-session`, `new-window`, `send-keys`, and `capture-pane`.

The default backend is Orca.
Override it with:

```powershell
$env:FM_BACKEND = 'psmux'
```

or with local config:

```powershell
New-Item -ItemType Directory -Force config
Set-Content config/backend psmux
```

If Orca is installed outside the default per-user location, set:

```powershell
$env:FM_ORCA_CMD = 'D:\tools\Orca\resources\bin\orca.cmd'
```

or write the path into `config/orca-command`.

## Start

From this repository:

```powershell
pwsh .\pwsh\fm-session-start.ps1
```

Use a custom psmux session name when you select the psmux backend and do not want to share the default `firstmate` session:

```powershell
$env:FM_PSMUX_SESSION = 'firstmate-dev'
pwsh .\pwsh\fm-session-start.ps1
```

Attach to the psmux session when you use psmux and want to watch panes:

```powershell
psmux attach -t firstmate
```

## Register a project

Clone or place projects under `projects/`, or pass an absolute project path to `fm-spawn.ps1`.

Example with an existing local repository:

```powershell
pwsh .\pwsh\fm-spawn.ps1 `
  -Id inspect-backend `
  -Project D:\yjky\yj-app-backend `
  -Kind scout `
  -Harness codex `
  -Prompt 'Investigate the backend test commands and write a concise report.'
```

The script creates:

- `data/<id>/brief.md`;
- `state/<id>.meta`;
- `state/<id>.status`;
- an Orca-managed worktree by default, or `worktrees/<id>` when `FM_BACKEND=psmux`;
- an Orca terminal by default, or a psmux window named `fm-<id>` when `FM_BACKEND=psmux`.

## Inspect and steer

Capture a task endpoint:

```powershell
pwsh .\pwsh\fm-peek.ps1 inspect-backend
```

Send text:

```powershell
pwsh .\pwsh\fm-send.ps1 inspect-backend 'Continue and update the report path in your final status.'
```

Send a key:

```powershell
pwsh .\pwsh\fm-send.ps1 inspect-backend -Key C-c
```

## Teardown

Scout teardown requires a report unless forced:

```powershell
pwsh .\pwsh\fm-teardown.ps1 inspect-backend
```

Ship teardown is intentionally conservative.
It refuses by default because the MVP does not yet verify that the work has landed.
Use `-Force` only after reviewing and preserving the work:

```powershell
pwsh .\pwsh\fm-teardown.ps1 feature-task -Force
```

## Design notes

Orca is the default because its Windows CLI can create worktrees and managed terminals directly.
psmux remains a good fallback because it keeps the tmux command surface firstmate already relies on.
The PowerShell layer still handles Windows-specific quoting, path handling, and safe metadata writes.

The current scripts use `"${session}:window"` style target construction.
In PowerShell, `"$session:window"` is parsed like a scoped variable and produces an empty target.
