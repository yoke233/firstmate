#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Id,

    [Parameter(Mandatory)]
    [string] $Project,

    [ValidateSet('ship', 'scout')]
    [string] $Kind = 'ship',

    [ValidateSet('codex', 'claude', 'opencode', 'pi', 'grok', 'manual')]
    [string] $Harness = 'codex',

    [ValidateSet('orca', 'psmux')]
    [string] $Backend,

    [string] $Prompt,

    [string] $LaunchCommand,

    [switch] $NoLaunch
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FirstmatePwsh.psm1') -Force -DisableNameChecking

Initialize-FmHome

$projectPath = Resolve-FmProjectPath -Project $Project
& git -C $projectPath rev-parse --show-toplevel *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Project is not a git repository: $projectPath"
}

if ([string]::IsNullOrWhiteSpace($Id)) {
    $basis = if ($Prompt) { $Prompt } else { Split-Path -Leaf $projectPath }
    $Id = New-FmTaskId -Title $basis
}
Assert-FmTaskId -Id $Id | Out-Null
if ([string]::IsNullOrWhiteSpace($Backend)) {
    $Backend = Get-FmBackend
}
if ($Backend -notin @('orca', 'psmux')) {
    throw "Unsupported Windows backend '$Backend'. Expected orca or psmux."
}

$taskDir = Join-FmPath -Kind data -Child $Id
$briefPath = Join-Path -Path $taskDir -ChildPath 'brief.md'
$metaPath = Get-FmMetaPath -Id $Id
$statusPath = Get-FmStatusPath -Id $Id
foreach ($existingPath in @($taskDir, $metaPath, $statusPath)) {
    if (Test-Path -LiteralPath $existingPath) {
        throw "Refusing to overwrite existing task state: $existingPath"
    }
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $reportPath = Join-Path -Path $taskDir -ChildPath 'report.md'
    $Prompt = @"
You are a firstmate crewmate running on Windows PowerShell.
Task id: $Id
Task kind: $Kind

Work only inside this task worktree.
For ship work, commit your changes on the task branch and report the result.
For scout work, do not modify project code; write findings to $reportPath.
Append concise status lines to $statusPath when the state changes.
"@
}

$window = "fm-$Id"
$branch = ''
$session = ''
$target = ''
$terminal = ''
$orcaWorktreeId = ''
$worktreePath = ''
$createdPsmuxWorktree = $false
try {
    if ($Backend -eq 'orca') {
        $orcaTask = New-FmOrcaTask -Name $window -ProjectPath $projectPath
        $worktreePath = $orcaTask.WorktreePath
        $orcaWorktreeId = $orcaTask.WorktreeId
        $terminal = $orcaTask.Terminal
        $target = $terminal
    } else {
        $worktreeRoot = Join-FmPath -Kind worktrees
        $worktreePath = Join-Path -Path $worktreeRoot -ChildPath $Id
        if (Test-Path -LiteralPath $worktreePath) {
            throw "Worktree path already exists: $worktreePath"
        }

        $branch = if ($Kind -eq 'ship') { "fm/$Id" } else { '' }
        if ($Kind -eq 'ship') {
            & git -C $projectPath worktree add -b $branch $worktreePath HEAD
        } else {
            & git -C $projectPath worktree add --detach $worktreePath HEAD
        }
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree add failed for $worktreePath"
        }
        $createdPsmuxWorktree = $true

        $session = Get-FmSessionName
        $target = New-FmPsmuxWindow -WindowName $window -WorkingDirectory $worktreePath -SessionName $session
    }

    New-Item -ItemType Directory -Path $taskDir | Out-Null
    Set-Content -LiteralPath $briefPath -Value $Prompt -Encoding utf8

    $meta = [ordered]@{
        id = $Id
        kind = $Kind
        backend = $Backend
        session = $session
        window = $window
        target = $target
        terminal = $terminal
        orca_worktree_id = $orcaWorktreeId
        project = $projectPath
        worktree = $worktreePath
        branch = $branch
        harness = $Harness
        brief = $briefPath
        created_at = (Get-Date).ToString('o')
    }
    Write-FmMeta -Id $Id -Meta $meta
} catch {
    $spawnError = $_.Exception.Message
    $cleanupErrors = [System.Collections.Generic.List[string]]::new()
    if ($Backend -eq 'orca' -and ($terminal -or $orcaWorktreeId)) {
        try {
            Close-FmOrcaTask -Terminal $terminal -WorktreeId $orcaWorktreeId
        } catch {
            $cleanupErrors.Add($_.Exception.Message)
        }
    } elseif ($Backend -eq 'psmux') {
        if ($target) {
            Invoke-FmPsmux -Arguments @('kill-window', '-t', $target) -AllowFailure
        }
        if ($createdPsmuxWorktree -and (Test-Path -LiteralPath $worktreePath)) {
            & git -C $projectPath worktree remove --force $worktreePath *> $null
            if ($LASTEXITCODE -ne 0) {
                $cleanupErrors.Add("git worktree remove failed for $worktreePath")
            }
        }
        if ($branch -and $createdPsmuxWorktree) {
            & git -C $projectPath branch -D $branch *> $null
            if ($LASTEXITCODE -ne 0) {
                $cleanupErrors.Add("git branch cleanup failed for $branch")
            }
        }
    }

    if ($cleanupErrors.Count -eq 0) {
        foreach ($createdPath in @($metaPath, $statusPath, $taskDir)) {
            if (Test-Path -LiteralPath $createdPath) {
                Remove-Item -LiteralPath $createdPath -Recurse -Force
            }
        }
        throw $spawnError
    }

    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
    if (-not (Test-Path -LiteralPath $briefPath)) {
        Set-Content -LiteralPath $briefPath -Value $Prompt -Encoding utf8
    }
    Write-FmMeta -Id $Id -Meta ([ordered]@{
        id = $Id
        kind = $Kind
        backend = $Backend
        session = $session
        window = $window
        target = $target
        terminal = $terminal
        orca_worktree_id = $orcaWorktreeId
        project = $projectPath
        worktree = $worktreePath
        branch = $branch
        harness = $Harness
        brief = $briefPath
        spawn_cleanup_required = 'true'
        created_at = (Get-Date).ToString('o')
    })
    Add-FmStatus -Id $Id -Line "blocked: spawn failed and cleanup needs attention: $($cleanupErrors -join '; ')"
    throw "Spawn failed: $spawnError Cleanup was incomplete and task records were preserved: $($cleanupErrors -join '; ')"
}

if ($NoLaunch -or $Harness -eq 'manual') {
    Add-FmStatus -Id $Id -Line "parked: $Backend endpoint created; launch skipped"
    "spawned: id=$Id backend=$Backend target=$target worktree=$worktreePath launch=skipped"
    return
}

if ([string]::IsNullOrWhiteSpace($LaunchCommand)) {
    $briefLiteral = ConvertTo-FmPowerShellLiteral -Value $briefPath
    $LaunchCommand = switch ($Harness) {
        'codex' { "codex --dangerously-bypass-approvals-and-sandbox (Get-Content -Raw -LiteralPath $briefLiteral)" }
        'claude' { "claude --dangerously-skip-permissions (Get-Content -Raw -LiteralPath $briefLiteral)" }
        'opencode' { "opencode --prompt (Get-Content -Raw -LiteralPath $briefLiteral)" }
        'pi' { "pi (Get-Content -Raw -LiteralPath $briefLiteral)" }
        'grok' { "grok --always-approve (Get-Content -Raw -LiteralPath $briefLiteral)" }
    }
}

try {
    if ($Backend -eq 'orca') {
        Send-FmOrcaText -Terminal $target -Text $LaunchCommand
    } else {
        Send-FmPsmuxText -Target $target -Text $LaunchCommand
    }
    Add-FmStatus -Id $Id -Line "working: launched $Harness"
} catch {
    Add-FmStatus -Id $Id -Line "blocked: launch failed; endpoint and worktree preserved: $($_.Exception.Message)"
    throw "Task '$Id' was created, but the worker launch failed. Its endpoint, worktree, and metadata were preserved for retry or cleanup. $($_.Exception.Message)"
}
"spawned: id=$Id backend=$Backend target=$target worktree=$worktreePath harness=$Harness"
