[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $InstallerPath,
    [Parameter(Mandatory)] [string] $StageDirectory,
    [Parameter(Mandatory)] [string] $TempBase,
    [string] $TestLanguage = 'ar'
)

$ErrorActionPreference = 'Stop'
$application = 'Super Booster'
$registryBase = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
$testRegistration = Join-Path $registryBase '{2FB21D94-87B2-432C-A6D9-6359C478234D}_is1'
$startLink = Join-Path ([Environment]::GetFolderPath('Programs', 'DoNotVerify')) "$application.lnk"
$desktopLink = Join-Path ([Environment]::GetFolderPath('DesktopDirectory', 'DoNotVerify')) "$application.lnk"
$silent = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
$expectedVersion = (Get-Item -LiteralPath $InstallerPath).VersionInfo.ProductVersion.Trim()
$sourceExe = Join-Path $StageDirectory 'super_booster.exe'
$sourceHash = (Get-FileHash -LiteralPath $sourceExe -Algorithm SHA256).Hash

function Invoke-Installer([string] $File, [string[]] $Options) {
    $process = Start-Process -FilePath $File -ArgumentList $Options -WindowStyle Hidden -PassThru
    try {
        if (-not $process.WaitForExit(180000)) {
            if (-not $process.HasExited) { $process.Kill($true) }
            throw 'Installer process timed out.'
        }
        if ($process.ExitCode -ne 0) { throw "Installer process returned $($process.ExitCode)." }
    } finally { $process.Dispose() }
}

function Get-IconHash([string] $File) {
    $icon = [Drawing.Icon]::ExtractAssociatedIcon($File)
    if (-not $icon) { throw 'Could not extract the Windows icon.' }
    try {
        $stream = [IO.MemoryStream]::new()
        $bitmap = $icon.ToBitmap()
        try {
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream.ToArray()))
        } finally {
            $bitmap.Dispose()
            $stream.Dispose()
        }
    } finally { $icon.Dispose() }
}

function Test-Shortcut([string] $Path, [bool] $ShouldExist, [string] $ExpectedTarget) {
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -ne $ShouldExist) {
        throw 'Shortcut creation did not match the selected tasks.'
    }
    if ($ShouldExist) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($Path)
            try {
                if ($shortcut.TargetPath -ine $ExpectedTarget) { throw 'The shortcut points to an unexpected executable.' }
            } finally { [void] [Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        } finally { [void] [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}

function Assert-CleanRegistration {
    foreach ($path in $testRegistration, $startLink, $desktopLink) {
        if (Test-Path -LiteralPath $path) { throw 'An existing verification registration or shortcut was found.' }
    }
}

function Wait-UninstallCompletion([string] $LogPath) {
    # The initial Inno process exits before the child runs the cleanup callback.
    for ($i = 0; $i -lt 100; $i++) {
        if ((Test-Path -LiteralPath $LogPath) -and
            (Select-String -LiteralPath $LogPath -SimpleMatch 'Super Booster uninstall completed.' -Quiet)) {
            return
        }
        Start-Sleep -Milliseconds 200
    }
    if (Test-Path -LiteralPath $LogPath) { Get-Content -LiteralPath $LogPath -Tail 12 | Write-Host }
    throw 'The second phase of uninstall did not finish.'
}

function Test-InstallCycle([bool] $Start, [bool] $Desktop, [bool] $Purge, [bool] $KeepUnrelatedFile) {
    Assert-CleanRegistration
    Write-Host "Verifying Start menu=$Start, desktop=$Desktop, cleanup=$Purge, unrelated file=$KeepUnrelatedFile"
    $folder = Join-Path $TempBase ('verify-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder | Out-Null
    $installRoot = Join-Path $folder $application
    $exe = Join-Path $installRoot 'super_booster.exe'
    $settings = Join-Path $installRoot 'booster_settings.json'
    $route = Join-Path $installRoot 'booster_audio_route.json'
    $update = Join-Path $installRoot 'booster_update.ini'
    $otherData = Join-Path $installRoot 'unrelated-user-file.txt'
    $setupLog = Join-Path $folder 'setup.log'
    $uninstallLog = Join-Path $folder 'uninstall.log'
    $tasks = @(if ($Start) { 'startmenu' }; if ($Desktop) { 'desktopicon' }) -join ','
    $registeredUninstaller = $null

    Invoke-Installer $InstallerPath ($silent + @('/SP-', "/LANG=$TestLanguage", "/TASKS=$tasks", ('/DIR="{0}"' -f $installRoot), ('/LOG="{0}"' -f $setupLog)))
    try {
        $entry = Get-ItemProperty -LiteralPath $testRegistration
        $uninstallCommand = [string] $entry.UninstallString
        if ($uninstallCommand -match '^"([^"]+)"') {
            $registeredUninstaller = $Matches[1]
        }
        if (!$registeredUninstaller -or !$registeredUninstaller.StartsWith($installRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The verified uninstaller is outside the test installation.'
        }
        if ($entry.DisplayVersion -ne $expectedVersion -or $entry.InstallLocation.TrimEnd('\') -ine $installRoot) {
            throw 'The installer did not register the expected application and version.'
        }
        if (-not (Select-String -LiteralPath $setupLog -SimpleMatch "Super Booster installer language: $TestLanguage" -Quiet)) {
            throw 'The requested setup language was not activated.'
        }
        if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -cne $sourceHash -or (Get-IconHash $exe) -cne $script:releaseIcon) {
            throw 'The installed executable or its icon differs from the release build.'
        }
        Test-Shortcut $startLink $Start $exe
        Test-Shortcut $desktopLink $Desktop $exe
        Set-Content -LiteralPath $settings -Value '{"qa":true}'
        Set-Content -LiteralPath $route -Value '{"qa":true}'
        Set-Content -LiteralPath $update -Value '[General]', 'automaticChecks=false'
        if ($KeepUnrelatedFile) { Set-Content -LiteralPath $otherData -Value 'keep' }
    } finally {
        if ($registeredUninstaller -and (Test-Path -LiteralPath $registeredUninstaller -PathType Leaf)) {
            $options = $silent + @(('/LOG="{0}"' -f $uninstallLog))
            if ($Purge) { $options += '/PURGEDATA' }
            Invoke-Installer $registeredUninstaller $options
            Wait-UninstallCompletion $uninstallLog
        }
    }

    Assert-CleanRegistration
    if (Test-Path -LiteralPath $exe) { throw 'Uninstall left the application executable.' }
    foreach ($appData in $settings, $route, $update) {
        if ((Test-Path -LiteralPath $appData) -eq $Purge) {
            Get-Content -LiteralPath $uninstallLog -Tail 18 | Write-Host
            throw 'Uninstall did not honor the app-data choice.'
        }
    }
    if ($KeepUnrelatedFile -and ((Get-Content -LiteralPath $otherData -Raw).Trim() -cne 'keep')) {
        throw 'Optional cleanup did not preserve unrelated files.'
    }
    if ($Purge -and -not $KeepUnrelatedFile) {
        for ($i = 0; $i -lt 25 -and (Test-Path -LiteralPath $installRoot); $i++) { Start-Sleep -Milliseconds 200 }
        if (Test-Path -LiteralPath $installRoot) {
            $remaining = (Get-ChildItem -LiteralPath $installRoot -Force | Select-Object -ExpandProperty Name) -join ', '
            throw "Optional cleanup left the empty installation folder or residual files ($remaining)."
        }
    }
}

Add-Type -AssemblyName System.Drawing
$script:releaseIcon = Get-IconHash $InstallerPath
if ((Get-IconHash $sourceExe) -cne $script:releaseIcon) {
    throw 'The setup installers and application do not share the branded Windows icon.'
}
New-Item -ItemType Directory -Path $TempBase -Force | Out-Null
Test-InstallCycle -Start $true -Desktop $false -Purge $false -KeepUnrelatedFile $false
Test-InstallCycle -Start $false -Desktop $true -Purge $true -KeepUnrelatedFile $true
Test-InstallCycle -Start $true -Desktop $true -Purge $true -KeepUnrelatedFile $false
'Passed application and setup icon checks, independent shortcut selections, and both uninstall choices.'
