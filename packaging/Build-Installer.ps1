[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $StageDirectory,

    [Parameter(Mandatory)]
    [string] $OutputDirectory,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    [string] $IsccPath = 'ISCC.exe'
)

$ErrorActionPreference = 'Stop'
$compiler = (Get-Command -Name $IsccPath -CommandType Application).Source
$stage = (Resolve-Path -LiteralPath $StageDirectory).Path
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$script = Join-Path $PSScriptRoot 'SuperBooster.iss'

if ($output.TrimEnd('\').StartsWith($stage.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $output.TrimEnd('\') -ieq $stage.TrimEnd('\')) {
    throw 'Choose an output folder outside the staged application payload.'
}

foreach ($file in 'super_booster.exe', 'super_booster_update_helper.exe', 'Qt6Core.dll', 'Qt6WebSockets.dll', 'platforms\qwindows.dll') {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $file) -PathType Leaf)) {
        throw "The staged Windows payload is missing $file. Build the app and run windeployqt first."
    }
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
& $compiler "/DAppVersion=$Version" "/DStageDirectory=$stage" "/O$output" $script
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE."
}

Get-Item -LiteralPath (Join-Path $output "SuperBooster-$Version-windows-x64-setup.exe")
