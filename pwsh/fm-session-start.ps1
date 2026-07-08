#requires -Version 7.0
[CmdletBinding()]
param(
    [switch] $NoEnsureBackend
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FirstmatePwsh.psm1') -Force -DisableNameChecking

Initialize-FmHome

function Write-Section {
    param([Parameter(Mandatory)][string] $Title)
    Write-Output ''
    Write-Output '================================================================================'
    Write-Output $Title
    Write-Output '================================================================================'
}

function Write-FileOrAbsent {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Label
    )

    Write-Output ''
    Write-Output $Label
    Write-Output '--------------------------------------------------------------------------------'
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path).Length -gt 0) {
            Get-Content -LiteralPath $Path
        } else {
            '(present, empty)'
        }
    } else {
        'ABSENT'
    }
}

Write-Section "SESSION START - $(Get-FmHome)"

Write-Output ''
Write-Output 'TOOLCHAIN'
Write-Output '--------------------------------------------------------------------------------'
foreach ($tool in @('psmux', 'git', 'gh', 'node', 'jq', 'codex', 'claude')) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd) {
        "OK: $tool -> $($cmd.Source)"
    } else {
        "MISSING: $tool"
    }
}
try {
    "OK: orca -> $(Get-FmOrcaCommand)"
} catch {
    "MISSING: orca ($($_.Exception.Message))"
}

Write-Output ''
Write-Output 'BACKEND'
Write-Output '--------------------------------------------------------------------------------'
$backend = Get-FmBackend
"BACKEND: $backend"
if ($backend -eq 'orca') {
    if ($NoEnsureBackend) {
        'ORCA: not checked because -NoEnsureBackend was passed'
    } else {
        $status = Get-FmOrcaStatus
        "ORCA_RUNTIME: reachable=$($status.result.runtime.reachable) state=$($status.result.runtime.state) graph=$($status.result.graph.state)"
    }
} else {
    $session = Get-FmSessionName
    if ($NoEnsureBackend) {
        "PSMUX_SESSION: $session (not ensured because -NoEnsureBackend was passed)"
    } else {
        Ensure-FmPsmuxSession -SessionName $session
        "PSMUX_SESSION: $session"
        Invoke-FmPsmuxText -Arguments @('list-windows', '-t', $session) -AllowFailure
    }
}

Write-Section 'CONTEXT'
Write-FileOrAbsent -Path (Join-FmPath -Kind data -Child 'projects.md') -Label 'data/projects.md'
Write-FileOrAbsent -Path (Join-FmPath -Kind data -Child 'backlog.md') -Label 'data/backlog.md'
Write-FileOrAbsent -Path (Join-FmPath -Kind data -Child 'captain.md') -Label 'data/captain.md'
Write-FileOrAbsent -Path (Join-FmPath -Kind data -Child 'learnings.md') -Label 'data/learnings.md'

Write-Section 'TASKS'
$metaFiles = Get-ChildItem -LiteralPath (Join-FmPath -Kind state) -Filter '*.meta' -ErrorAction SilentlyContinue
if (-not $metaFiles) {
    '(no task metadata)'
} else {
    foreach ($file in $metaFiles) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $meta = Read-FmMeta -Id $id
        $lastStatus = '(no status)'
        $statusPath = Get-FmStatusPath -Id $id
        if (Test-Path -LiteralPath $statusPath) {
            $lastStatus = Get-Content -LiteralPath $statusPath | Select-Object -Last 1
        }
        "$id kind=$($meta['kind']) backend=$($meta['backend']) target=$($meta['target']) status=$lastStatus"
    }
}

Write-Output ''
Write-Output 'NEXT'
Write-Output '--------------------------------------------------------------------------------'
'Use pwsh/fm-spawn.ps1 to create a task, pwsh/fm-peek.ps1 to inspect it, and pwsh/fm-send.ps1 to steer it.'
