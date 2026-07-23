#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Selector,

    [Parameter(Position = 1)]
    [string] $Text,

    [ValidateSet('Enter', 'C-c')]
    [string] $Key,

    [switch] $NoEnter
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FirstmatePwsh.psm1') -Force -DisableNameChecking

if ($Key -and $PSBoundParameters.ContainsKey('Text')) {
    throw 'Text and -Key cannot be used together.'
}
if ($NoEnter -and $Key) {
    throw '-NoEnter cannot be used with -Key.'
}

$endpoint = Resolve-FmEndpoint -Selector $Selector
$target = $endpoint.Target
if ($Key) {
    if ($endpoint.Backend -eq 'orca') {
        Send-FmOrcaKey -Terminal $target -Key $Key
    } else {
        Send-FmPsmuxKey -Target $target -Key $Key
    }
    "sent key: $Key -> $target"
    return
}

if ([string]::IsNullOrEmpty($Text)) {
    throw 'Text is required unless -Key is used.'
}

if ($endpoint.Backend -eq 'orca') {
    Send-FmOrcaText -Terminal $target -Text $Text -NoEnter:$NoEnter
} else {
    Send-FmPsmuxText -Target $target -Text $Text -NoEnter:$NoEnter
}
"sent text -> $target"
