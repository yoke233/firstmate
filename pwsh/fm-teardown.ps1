#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Id,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FirstmatePwsh.psm1') -Force -DisableNameChecking

$meta = Read-FmMeta -Id $Id
$kind = $meta['kind']
$endpoint = Resolve-FmEndpoint -Selector $Id
$target = $endpoint.Target
$worktree = $meta['worktree']
$project = $meta['project']

if ($kind -eq 'ship' -and -not $Force) {
    throw 'Refusing to tear down ship work without -Force. Review and land the work first, then rerun with -Force when it is safe to discard the worktree.'
}

if ($kind -eq 'scout' -and -not $Force) {
    $report = Join-Path -Path (Join-FmPath -Kind data -Child $Id) -ChildPath 'report.md'
    if (-not (Test-Path -LiteralPath $report)) {
        throw "Refusing to tear down scout work without report.md. Expected: $report"
    }
}

if ($endpoint.Backend -eq 'orca') {
    Close-FmOrcaTask -Terminal $meta['terminal'] -WorktreeId $meta['orca_worktree_id']
} else {
    Invoke-FmPsmux -Arguments @('kill-window', '-t', $target) -AllowFailure

    if (Test-Path -LiteralPath $worktree) {
        & git -C $project worktree remove --force $worktree
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree remove failed for $worktree"
        }
    }
}

Remove-Item -LiteralPath (Get-FmMetaPath -Id $Id) -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Get-FmStatusPath -Id $Id) -Force -ErrorAction SilentlyContinue

"torn down: $Id"
