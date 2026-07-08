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
if ([string]::IsNullOrWhiteSpace($Backend)) {
    $Backend = Get-FmBackend
}

$taskDir = Join-FmPath -Kind data -Child $Id
New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
$briefPath = Join-Path -Path $taskDir -ChildPath 'brief.md'

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = @"
You are a firstmate crewmate running on Windows PowerShell.
Task id: $Id
Task kind: $Kind

Work only inside this task worktree.
For ship work, commit your changes on the task branch and report the result.
For scout work, do not modify project code; write findings to data/$Id/report.md.
Append concise status lines to state/$Id.status when the state changes.
"@
}

Set-Content -LiteralPath $briefPath -Value $Prompt -Encoding utf8

$window = "fm-$Id"
$branch = ''
$session = ''
$target = ''
$terminal = ''
$orcaWorktreeId = ''
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

    $session = Get-FmSessionName
    $target = New-FmPsmuxWindow -WindowName $window -WorkingDirectory $worktreePath -SessionName $session
}

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

if ($Backend -eq 'orca') {
    Send-FmOrcaText -Terminal $target -Text $LaunchCommand
} else {
    Send-FmPsmuxText -Target $target -Text $LaunchCommand
}
Add-FmStatus -Id $Id -Line "working: launched $Harness"
"spawned: id=$Id backend=$Backend target=$target worktree=$worktreePath harness=$Harness"
