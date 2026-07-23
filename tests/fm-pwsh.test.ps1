#requires -Version 7.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'pwsh\FirstmatePwsh.psm1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("firstmate-pwsh-test-" + [Guid]::NewGuid().ToString('N'))
$originalHome = $env:FM_HOME
$originalPath = $env:PATH

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock] $Action,
        [Parameter(Mandatory)][string] $Like
    )

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notlike $Like) {
            throw "Expected error like '$Like', got: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected an error like '$Like', but the action succeeded."
}

try {
    $env:FM_HOME = $tempRoot
    Import-Module $modulePath -Force -DisableNameChecking
    Initialize-FmHome

    Assert-FmTaskId -Id 'valid-task-7' | Out-Null
    foreach ($invalidId in @('..\escape', 'a/b', 'UPPER', '.hidden', ('a' * 64))) {
        Assert-Throws -Action { Assert-FmTaskId -Id $invalidId | Out-Null } -Like 'Invalid task id*'
    }

    Assert-Throws -Action { Resolve-FmEndpoint -Selector 'missing-task' | Out-Null } -Like 'Task endpoint was not found*'
    $orca = Resolve-FmEndpoint -Selector 'term_example-1'
    if ($orca.Backend -ne 'orca' -or $orca.Target -ne 'term_example-1') {
        throw 'Explicit Orca endpoint did not resolve as Orca.'
    }
    $psmux = Resolve-FmEndpoint -Selector 'firstmate:fm-test'
    if ($psmux.Backend -ne 'psmux' -or $psmux.Target -ne 'firstmate:fm-test') {
        throw 'Explicit psmux endpoint did not resolve as psmux.'
    }

    Write-FmMeta -Id 'known-task' -Meta ([ordered]@{ backend = 'orca'; target = 'term_known' })
    $known = Resolve-FmEndpoint -Selector 'known-task'
    if ($known.Backend -ne 'orca' -or $known.Target -ne 'term_known') {
        throw 'Recorded task endpoint did not resolve from metadata.'
    }

    $parseErrors = @()
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'pwsh') -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') } | ForEach-Object {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        $parseErrors += $errors
    }
    if ($parseErrors.Count -gt 0) {
        throw "PowerShell parse errors: $($parseErrors.Message -join '; ')"
    }

    $sendOutput = & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-send.ps1') term_example text -Key Enter 2>&1
    if ($LASTEXITCODE -eq 0 -or ($sendOutput -join "`n") -notlike '*Text and -Key cannot be used together*') {
        throw 'fm-send did not reject conflicting text and key input before backend access.'
    }

    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-peek.ps1') term_example -Tail -1 *> $null
    if ($LASTEXITCODE -eq 0) {
        throw 'fm-peek accepted a negative tail length.'
    }

    $spawnPath = Join-Path $repoRoot 'pwsh\fm-spawn.ps1'
    $invalidSpawn = & pwsh -NoLogo -NoProfile -File $spawnPath -Id '..\escape' -Project $repoRoot -Backend psmux -NoLaunch 2>&1
    if ($LASTEXITCODE -eq 0 -or ($invalidSpawn -join "`n") -notlike '*Invalid task id*') {
        throw 'fm-spawn did not reject a path-unsafe task id before backend access.'
    }

    $duplicateDir = Join-FmPath -Kind data -Child 'duplicate-task'
    New-Item -ItemType Directory -Path $duplicateDir | Out-Null
    $duplicateSpawn = & pwsh -NoLogo -NoProfile -File $spawnPath -Id 'duplicate-task' -Project $repoRoot -Backend psmux -NoLaunch 2>&1
    if ($LASTEXITCODE -eq 0 -or ($duplicateSpawn -join "`n") -notlike '*Refusing to overwrite existing task state*') {
        throw 'fm-spawn did not protect an existing task directory.'
    }

    $fakeWorktree = Join-Path $tempRoot 'not-a-worktree'
    New-Item -ItemType Directory -Path $fakeWorktree | Out-Null
    Write-FmMeta -Id 'cleanup-test' -Meta ([ordered]@{
        kind = 'ship'
        backend = 'psmux'
        target = 'missing-session:missing-window'
        worktree = $fakeWorktree
        project = $repoRoot
    })
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-teardown.ps1') cleanup-test -Force *> $null
    if ($LASTEXITCODE -eq 0 -or -not (Test-Path -LiteralPath (Get-FmMetaPath -Id 'cleanup-test'))) {
        throw 'fm-teardown did not retain metadata after worktree removal failed.'
    }

    $fakeBin = Join-Path $tempRoot 'fake-bin'
    New-Item -ItemType Directory -Path $fakeBin | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeBin 'psmux.cmd') -Encoding ascii -Value @'
@echo off
if "%1"=="send-keys" exit /b 9
exit /b 0
'@
    $env:PATH = "$fakeBin$([System.IO.Path]::PathSeparator)$originalPath"

    $projectPath = Join-Path $tempRoot 'project'
    & git init -q $projectPath
    & git -C $projectPath config user.name 'PowerShell Test'
    & git -C $projectPath config user.email 'pwsh-test@example.invalid'
    Set-Content -LiteralPath (Join-Path $projectPath 'README.md') -Value 'fixture' -Encoding utf8
    & git -C $projectPath add README.md
    & git -C $projectPath commit -q -m 'fixture'
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the temporary Git fixture.'
    }

    & pwsh -NoLogo -NoProfile -File $spawnPath -Id 'scout-default' -Project $projectPath -Kind scout -Backend psmux -Harness manual -NoLaunch *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the default scout fixture.'
    }
    $scoutBrief = Get-Content -Raw -LiteralPath (Join-Path $tempRoot 'data\scout-default\brief.md')
    $expectedReport = Join-Path $tempRoot 'data\scout-default\report.md'
    $expectedStatus = Join-Path $tempRoot 'state\scout-default.status'
    if (-not $scoutBrief.Contains($expectedReport) -or -not $scoutBrief.Contains($expectedStatus)) {
        throw 'The default scout brief did not use the durable absolute report and status paths.'
    }
    Set-Content -LiteralPath $expectedReport -Value 'report' -Encoding utf8
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-teardown.ps1') scout-default *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not clean up the default scout fixture.'
    }

    & pwsh -NoLogo -NoProfile -File $spawnPath -Id 'ship-clean' -Project $projectPath -Kind ship -Backend psmux -Harness manual -NoLaunch *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the ship cleanup fixture.'
    }
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-teardown.ps1') ship-clean -Force *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not clean up the ship fixture.'
    }
    & git -C $projectPath show-ref --verify --quiet 'refs/heads/fm/ship-clean'
    if ($LASTEXITCODE -eq 0 -or (Test-Path -LiteralPath (Get-FmMetaPath -Id 'ship-clean'))) {
        throw 'Successful ship cleanup left its task branch or metadata behind.'
    }

    & pwsh -NoLogo -NoProfile -File $spawnPath -Id 'branch-guard' -Project $projectPath -Kind ship -Backend psmux -Harness manual -NoLaunch *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the branch guard fixture.'
    }
    $guardMeta = Read-FmMeta -Id 'branch-guard'
    $guardWorktree = $guardMeta['worktree']
    $guardMeta['branch'] = 'main'
    Write-FmMeta -Id 'branch-guard' -Meta $guardMeta
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-teardown.ps1') branch-guard -Force *> $null
    if ($LASTEXITCODE -eq 0 -or -not (Test-Path -LiteralPath $guardWorktree)) {
        throw 'Unexpected branch metadata did not stop cleanup before worktree removal.'
    }
    $guardMeta['branch'] = 'fm/branch-guard'
    Write-FmMeta -Id 'branch-guard' -Meta $guardMeta
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-teardown.ps1') branch-guard -Force *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not clean up the restored branch guard fixture.'
    }

    $launchFailure = & pwsh -NoLogo -NoProfile -File $spawnPath -Id 'launch-fail' -Project $projectPath -Kind scout -Backend psmux -Harness codex -LaunchCommand 'ignored' 2>&1
    if ($LASTEXITCODE -eq 0 -or -not (Test-Path -LiteralPath (Get-FmMetaPath -Id 'launch-fail'))) {
        throw 'A worker launch failure did not preserve recoverable task metadata.'
    }
    $launchStatus = Get-Content -Raw -LiteralPath (Get-FmStatusPath -Id 'launch-fail')
    if ($launchStatus -notlike '*launch failed*') {
        throw 'A worker launch failure did not record the recovery reason.'
    }
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-teardown.ps1') launch-fail -Force *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not clean up the preserved launch-failure fixture.'
    }

    $sessionOutput = & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'pwsh\fm-session-start.ps1') -NoEnsureBackend 2>&1
    if ($LASTEXITCODE -ne 0 -or ($sessionOutput -join "`n") -notlike '*data/captain-shared.md*') {
        throw 'fm-session-start did not produce the updated Windows context digest.'
    }

    'PASS: PowerShell task safety and syntax checks'
} finally {
    $env:FM_HOME = $originalHome
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
