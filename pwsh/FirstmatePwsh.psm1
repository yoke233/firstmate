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

function Capture-FmPsmuxPane {
    param([Parameter(Mandatory)][string] $Target)

    Invoke-FmPsmuxText -Arguments @('capture-pane', '-p', '-t', $Target)
}

Export-ModuleMember -Function @(
    'Get-FmRoot',
    'Get-FmHome',
    'Join-FmPath',
    'Initialize-FmHome',
    'Get-FmSessionName',
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
    'New-FmPsmuxWindow',
    'Send-FmPsmuxText',
    'Send-FmPsmuxKey',
    'Capture-FmPsmuxPane'
)
