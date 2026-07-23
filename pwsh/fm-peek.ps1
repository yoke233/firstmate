#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Selector,

    [ValidateRange(1, 10000)]
    [int] $Tail = 80
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FirstmatePwsh.psm1') -Force -DisableNameChecking

$endpoint = Resolve-FmEndpoint -Selector $Selector
if ($endpoint.Backend -eq 'orca') {
    $lines = Capture-FmOrcaTerminal -Terminal $endpoint.Target -Limit $Tail
} else {
    $lines = Capture-FmPsmuxPane -Target $endpoint.Target
}
$lines | Select-Object -Last $Tail
