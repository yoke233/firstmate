Set-StrictMode -Version Latest

function Get-FmRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-FmHome {
    if ($env:FM_HOME) {
        return [System.IO.Path]::GetFullPath($env:FM_HOME)
    }

    Get-FmRoot
}

function Join-FmPath {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('state', 'data', 'config', 'projects', 'worktrees')]
        [string] $Kind,

        [string] $Child
    )

    $base = Join-Path -Path (Get-FmHome) -ChildPath $Kind
    if ([string]::IsNullOrWhiteSpace($Child)) {
        return $base
    }

    Join-Path -Path $base -ChildPath $Child
}

function Initialize-FmHome {
    foreach ($name in @('state', 'data', 'config', 'projects', 'worktrees')) {
        $path = Join-FmPath -Kind $name
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
}

function Get-FmBackend {
    if ($env:FM_BACKEND) {
        return $env:FM_BACKEND.ToLowerInvariant()
    }

    $configPath = Join-FmPath -Kind config -Child 'backend'
    if (Test-Path -LiteralPath $configPath) {
        $line = Get-Content -LiteralPath $configPath | Where-Object { $_.Trim() } | Select-Object -First 1
        if ($line) {
            return $line.Trim().ToLowerInvariant()
        }
    }

    'orca'
}

function Get-FmSessionName {
    if ($env:FM_PSMUX_SESSION) {
        return $env:FM_PSMUX_SESSION
    }

    $configPath = Join-FmPath -Kind config -Child 'session-name'
    if (Test-Path -LiteralPath $configPath) {
        $line = Get-Content -LiteralPath $configPath | Where-Object { $_.Trim() } | Select-Object -First 1
        if ($line) {
            return $line.Trim()
        }
    }

    'firstmate'
}

function Get-FmOrcaCommand {
    if ($env:FM_ORCA_CMD) {
        if (Test-Path -LiteralPath $env:FM_ORCA_CMD) {
            return $env:FM_ORCA_CMD
        }
        throw "FM_ORCA_CMD points to a missing path: $env:FM_ORCA_CMD"
    }

    $configPath = Join-FmPath -Kind config -Child 'orca-command'
    if (Test-Path -LiteralPath $configPath) {
        $line = Get-Content -LiteralPath $configPath | Where-Object { $_.Trim() } | Select-Object -First 1
        if ($line) {
            $candidate = $line.Trim()
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
            throw "config/orca-command points to a missing path: $candidate"
        }
    }

    $cmd = Get-Command orca -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = $env:LOCALAPPDATA
    }
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $defaultPath = Join-Path -Path $localAppData -ChildPath 'Programs\Orca\resources\bin\orca.cmd'
        if (Test-Path -LiteralPath $defaultPath) {
            return $defaultPath
        }
    }

    throw 'orca was not found. Set FM_ORCA_CMD or config/orca-command, or install Orca in %LOCALAPPDATA%\Programs\Orca.'
}

function Invoke-FmNativeCommand {
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $output = & $Command @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "command failed with exit code ${code}: $Command $($Arguments -join ' ')$([Environment]::NewLine)$text"
    }

    $output
}

function Invoke-FmOrcaText {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    Invoke-FmNativeCommand -Command (Get-FmOrcaCommand) -Arguments $Arguments -AllowFailure:$AllowFailure
}

function Invoke-FmOrcaJson {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $output = Invoke-FmOrcaText -Arguments $Arguments -AllowFailure:$AllowFailure
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $text | ConvertFrom-Json
}

function Get-FmOrcaStatus {
    Invoke-FmOrcaJson -Arguments @('status', '--json')
}

function Test-FmOrcaReady {
    try {
        $status = Get-FmOrcaStatus
        return [bool]($status.ok -and $status.result.runtime.reachable -and $status.result.runtime.state -eq 'ready')
    } catch {
        return $false
    }
}

function Ensure-FmOrcaReady {
    if (Test-FmOrcaReady) {
        return
    }

    Invoke-FmOrcaJson -Arguments @('open', '--json') | Out-Null
    if (-not (Test-FmOrcaReady)) {
        throw 'Orca runtime is not ready after `orca open`.'
    }
}

function Get-FmPsmuxCommand {
    $cmd = Get-Command psmux -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $tmux = Get-Command tmux -ErrorAction SilentlyContinue
    if ($tmux) {
        return $tmux.Source
    }

    throw 'psmux was not found on PATH. Install it with: winget install psmux'
}

function Invoke-FmPsmux {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $cmd = Get-FmPsmuxCommand
    & $cmd @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "psmux failed with exit code ${code}: $cmd $($Arguments -join ' ')"
    }
}

function Invoke-FmPsmuxText {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $cmd = Get-FmPsmuxCommand
    $output = & $cmd @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "psmux failed with exit code ${code}: $cmd $($Arguments -join ' ')$([Environment]::NewLine)$text"
    }

    $output
}

function Test-FmPsmuxSession {
    param([Parameter(Mandatory)][string] $SessionName)

    $cmd = Get-FmPsmuxCommand
    & $cmd has-session -t $SessionName *> $null
    $LASTEXITCODE -eq 0
}

function Ensure-FmPsmuxSession {
    param([string] $SessionName = (Get-FmSessionName))

    if (Test-FmPsmuxSession -SessionName $SessionName) {
        return
    }

    Invoke-FmPsmux -Arguments @('new-session', '-d', '-s', $SessionName, '-n', 'firstmate', '--', 'pwsh', '-NoLogo', '-NoProfile')
}

function New-FmTaskId {
    param([string] $Title = 'task')

    $slug = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'task'
    }
    if ($slug.Length -gt 32) {
        $slug = $slug.Substring(0, 32).Trim('-')
    }

    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 4)
    "$slug-$suffix"
}

function Resolve-FmProjectPath {
    param([Parameter(Mandatory)][string] $Project)

    if ([System.IO.Path]::IsPathRooted($Project) -and (Test-Path -LiteralPath $Project)) {
        return (Resolve-Path -LiteralPath $Project).Path
    }

    if (Test-Path -LiteralPath $Project) {
        return (Resolve-Path -LiteralPath $Project).Path
    }

    $underProjects = Join-FmPath -Kind projects -Child $Project
    if (Test-Path -LiteralPath $underProjects) {
        return (Resolve-Path -LiteralPath $underProjects).Path
    }

    throw "Project path was not found: $Project"
}

function ConvertTo-FmPowerShellLiteral {
    param([AllowEmptyString()][string] $Value)

    "'" + ($Value -replace "'", "''") + "'"
}

function Get-FmMetaPath {
    param([Parameter(Mandatory)][string] $Id)

    Join-FmPath -Kind state -Child "$Id.meta"
}

function Get-FmStatusPath {
    param([Parameter(Mandatory)][string] $Id)

    Join-FmPath -Kind state -Child "$Id.status"
}

function Read-FmMeta {
    param([Parameter(Mandatory)][string] $Id)

    $path = Get-FmMetaPath -Id $Id
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Task metadata was not found: $path"
    }

    $meta = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -notmatch '^\s*([^#=][^=]*)=(.*)$') {
            continue
        }

        $key = $Matches[1].Trim()
        $value = $Matches[2]
        $meta[$key] = $value
    }

    $meta
}

function Write-FmMeta {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Meta
    )

    $path = Get-FmMetaPath -Id $Id
    $lines = foreach ($key in $Meta.Keys) {
        "$key=$($Meta[$key])"
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding utf8
}

function Add-FmStatus {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Line
    )

    $path = Get-FmStatusPath -Id $Id
    Add-Content -LiteralPath $path -Value $Line -Encoding utf8
}

function Resolve-FmTarget {
    param([Parameter(Mandatory)][string] $Selector)

    $metaPath = Get-FmMetaPath -Id $Selector
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Read-FmMeta -Id $Selector
        if ($meta.Contains('target')) {
            return $meta['target']
        }
        if ($meta.Contains('session') -and $meta.Contains('window')) {
            return "$($meta['session']):$($meta['window'])"
        }
    }

    if ($Selector.Contains(':') -or $Selector.StartsWith('%')) {
        return $Selector
    }

    "$(Get-FmSessionName):$Selector"
}

function Resolve-FmEndpoint {
    param([Parameter(Mandatory)][string] $Selector)

    $metaPath = Get-FmMetaPath -Id $Selector
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Read-FmMeta -Id $Selector
        $backend = if ($meta.Contains('backend')) { $meta['backend'] } else { 'psmux' }
        $target = if ($meta.Contains('target')) { $meta['target'] } else { Resolve-FmTarget -Selector $Selector }
        return [pscustomobject]@{
            Backend = $backend
            Target = $target
            Meta = $meta
        }
    }

    $backend = Get-FmBackend
    $target = Resolve-FmTarget -Selector $Selector
    if ($Selector.StartsWith('term_')) {
        $backend = 'orca'
        $target = $Selector
    }

    [pscustomobject]@{
        Backend = $backend
        Target = $target
        Meta = $null
    }
}

function New-FmPsmuxWindow {
    param(
        [Parameter(Mandatory)][string] $WindowName,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [string] $SessionName = (Get-FmSessionName)
    )

    Ensure-FmPsmuxSession -SessionName $SessionName
    Invoke-FmPsmux -Arguments @('new-window', '-d', '-t', $SessionName, '-n', $WindowName, '-c', $WorkingDirectory, '--', 'pwsh', '-NoLogo', '-NoProfile')
    "${SessionName}:$WindowName"
}

function New-FmOrcaTask {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $ProjectPath
    )

    Ensure-FmOrcaReady
    Invoke-FmOrcaJson -Arguments @('repo', 'add', '--path', $ProjectPath, '--json') | Out-Null
    $worktree = Invoke-FmOrcaJson -Arguments @(
        'worktree', 'create',
        '--repo', "path:$ProjectPath",
        '--name', $Name,
        '--no-parent',
        '--setup', 'skip',
        '--json'
    )

    $worktreeId = $worktree.result.worktree.id
    $worktreePath = $worktree.result.worktree.path
    $terminal = $null
    if (($worktree.result.PSObject.Properties.Name -contains 'terminal') -and $null -ne $worktree.result.terminal) {
        if ($worktree.result.terminal.PSObject.Properties.Name -contains 'handle') {
            $terminal = $worktree.result.terminal.handle
        }
    }
    if (-not $terminal) {
        $terminalResult = Invoke-FmOrcaJson -Arguments @(
            'terminal', 'create',
            '--worktree', "id:$worktreeId",
            '--title', $Name,
            '--command', 'pwsh -NoLogo -NoProfile',
            '--json'
        )
        $terminal = $terminalResult.result.terminal.handle
    }

    [pscustomobject]@{
        WorktreeId = $worktreeId
        WorktreePath = $worktreePath
        Terminal = $terminal
    }
}

function Send-FmPsmuxText {
    param(
        [Parameter(Mandatory)][string] $Target,
        [Parameter(Mandatory)][string] $Text,
        [switch] $NoEnter
    )

    Invoke-FmPsmux -Arguments @('send-keys', '-t', $Target, '-l', $Text)
    if (-not $NoEnter) {
        Invoke-FmPsmux -Arguments @('send-keys', '-t', $Target, 'Enter')
    }
}

function Send-FmPsmuxKey {
    param(
        [Parameter(Mandatory)][string] $Target,
        [Parameter(Mandatory)][string] $Key
    )

    Invoke-FmPsmux -Arguments @('send-keys', '-t', $Target, $Key)
}

function Send-FmOrcaText {
    param(
        [Parameter(Mandatory)][string] $Terminal,
        [Parameter(Mandatory)][string] $Text,
        [switch] $NoEnter
    )

    $args = @('terminal', 'send', '--terminal', $Terminal, '--text', $Text, '--json')
    if (-not $NoEnter) {
        $args += '--enter'
    }
    Invoke-FmOrcaJson -Arguments $args | Out-Null
}

function Send-FmOrcaKey {
    param(
        [Parameter(Mandatory)][string] $Terminal,
        [Parameter(Mandatory)][string] $Key
    )

    switch ($Key) {
        'Enter' { Invoke-FmOrcaJson -Arguments @('terminal', 'send', '--terminal', $Terminal, '--enter', '--json') | Out-Null }
        'C-c' { Invoke-FmOrcaJson -Arguments @('terminal', 'send', '--terminal', $Terminal, '--interrupt', '--json') | Out-Null }
        default { throw "Unsupported Orca key: $Key" }
    }
}

function Capture-FmPsmuxPane {
    param([Parameter(Mandatory)][string] $Target)

    Invoke-FmPsmuxText -Arguments @('capture-pane', '-p', '-t', $Target)
}

function Capture-FmOrcaTerminal {
    param(
        [Parameter(Mandatory)][string] $Terminal,
        [int] $Limit = 200
    )

    $read = Invoke-FmOrcaJson -Arguments @('terminal', 'read', '--terminal', $Terminal, '--limit', "$Limit", '--json')
    if ($read -and $read.result -and $read.result.terminal -and $read.result.terminal.tail) {
        return $read.result.terminal.tail
    }
    @()
}

function Close-FmOrcaTask {
    param(
        [string] $Terminal,
        [string] $WorktreeId
    )

    if ($Terminal) {
        Invoke-FmOrcaJson -Arguments @('terminal', 'close', '--terminal', $Terminal, '--json') -AllowFailure | Out-Null
    }
    if ($WorktreeId) {
        Invoke-FmOrcaJson -Arguments @('worktree', 'rm', '--worktree', "id:$WorktreeId", '--force', '--json') -AllowFailure | Out-Null
    }
}

Export-ModuleMember -Function @(
    'Get-FmRoot',
    'Get-FmHome',
    'Join-FmPath',
    'Initialize-FmHome',
    'Get-FmBackend',
    'Get-FmSessionName',
    'Get-FmOrcaCommand',
    'Invoke-FmOrcaText',
    'Invoke-FmOrcaJson',
    'Get-FmOrcaStatus',
    'Test-FmOrcaReady',
    'Ensure-FmOrcaReady',
    'Get-FmPsmuxCommand',
    'Invoke-FmPsmux',
    'Invoke-FmPsmuxText',
    'Test-FmPsmuxSession',
    'Ensure-FmPsmuxSession',
    'New-FmTaskId',
    'Resolve-FmProjectPath',
    'ConvertTo-FmPowerShellLiteral',
    'Get-FmMetaPath',
    'Get-FmStatusPath',
    'Read-FmMeta',
    'Write-FmMeta',
    'Add-FmStatus',
    'Resolve-FmTarget',
    'Resolve-FmEndpoint',
    'New-FmPsmuxWindow',
    'New-FmOrcaTask',
    'Send-FmPsmuxText',
    'Send-FmPsmuxKey',
    'Send-FmOrcaText',
    'Send-FmOrcaKey',
    'Capture-FmPsmuxPane',
    'Capture-FmOrcaTerminal',
    'Close-FmOrcaTask'
)
