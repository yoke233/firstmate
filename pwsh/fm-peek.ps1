#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Selector,

    [int] $Tail = 80
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FirstmatePwsh.psm1') -Force -DisableNameChecking

$target = Resolve-FmTarget -Selector $Selector
$lines = Capture-FmPsmuxPane -Target $target
if ($Tail -gt 0) {
    $lines | Select-Object -Last $Tail
} else {
    $lines
}
