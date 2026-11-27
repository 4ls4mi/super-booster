[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $InstallerPath,
    [Parameter(Mandatory)] [string] $StageDirectory,
    [Parameter(Mandatory)] [string] $TempBase
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'The upgrade verification requires a fresh GitHub-hosted Windows profile.'
}

$previousVersion = '2.0.1'
$previousSha256 = 'A7FD81DAF3918CBF66F93DAE80F6C6C2D71C08EDD795723AEFF4EBADAD9319CF'
$candidate = Get-Item -LiteralPath $InstallerPath
if ($candidate.Name -cnotmatch '^SuperBooster-([0-9]+\.[0-9]+\.[0-9]+)-windows-x64-setup\.exe$') {
    throw 'The candidate installer filename does not match its release.'
}
$expectedVersion = $Matches[1]
if ([version] $expectedVersion -le [version] $previousVersion) {
    throw 'The candidate is not newer than the pinned previous release.'
}
$stage = (Resolve-Path -LiteralPath $StageDirectory).Path
$exeDigest = (Get-FileHash -LiteralPath (Join-Path $stage 'super_booster.exe')).Hash
$sourceHelper = Join-Path $stage 'super_booster_update_helper.exe'
if (-not (Test-Path -LiteralPath $sourceHelper -PathType Leaf)) {
    throw 'The staged release is missing its update helper.'
}

$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{2FB21D94-87B2-432C-A6D9-6359C478234D}_is1'
$startLink = Join-Path ([Environment]::GetFolderPath('Programs', 'DoNotVerify')) 'Super Booster.lnk'
$desktopLink = Join-Path ([Environment]::GetFolderPath('DesktopDirectory', 'DoNotVerify')) 'Super Booster.lnk'
foreach ($path in $registry, $startLink, $desktopLink) {
    if (Test-Path -LiteralPath $path) { throw 'Super Booster is already registered in this profile.' }
}

$base = New-Item -ItemType Directory -Path $TempBase -Force
$work = New-Item -ItemType Directory -Path (Join-Path $base.FullName ('handoff-' + [guid]::NewGuid().ToString('N')))
$installDir = Join-Path $work.FullName 'Super Booster'
$exe = Join-Path $installDir 'super_booster.exe'
$scratch = New-Item -ItemType Directory -Path (Join-Path $work.FullName 'update scratch')
$priorInstaller = Join-Path $work.FullName "SuperBooster-$previousVersion-windows-x64-setup.exe"
$ready = Join-Path $scratch.FullName 'update-ready'
$confirmed = Join-Path $scratch.FullName 'update-confirm'
$errorMarker = Join-Path $scratch.FullName 'update-error.txt'
$setupLog = Join-Path $scratch.FullName 'setup.log'
$cleanupLog = Join-Path $work.FullName 'uninstall.log'
$silent = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
$oldProcess = $null
$handoff = $null
$previousQtBackend = $env:QT_QUICK_BACKEND

function Wait-ForCondition([scriptblock] $Check, [int] $Seconds, [string] $Failure) {
    $time = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Check) { return }
        Start-Sleep -Milliseconds 200
    } while ($time.Elapsed.TotalSeconds -lt $Seconds)
    throw $Failure
}

function Wait-ForProcess([Diagnostics.Process] $Process, [int] $Seconds, [string] $Stage) {
    if (-not $Process.WaitForExit($Seconds * 1000)) {
        if (-not $Process.HasExited) { $Process.Kill($true) }
        throw "$Stage timed out."
    }
    if ($Process.ExitCode -ne 0) { throw "$Stage returned exit code $($Process.ExitCode)." }
}

function Get-FixtureProcesses {
    foreach ($process in (Get-Process -Name 'super_booster' -ErrorAction SilentlyContinue)) {
        try {
            if (-not $process.HasExited -and $process.MainModule.FileName -ieq $exe) {
                $process
            }
        } catch [InvalidOperationException] {
        } catch [System.ComponentModel.Win32Exception] {
        }
    }
}

function Assert-DesktopOnly {
    if ((Test-Path -LiteralPath $startLink) -or -not (Test-Path -LiteralPath $desktopLink -PathType Leaf)) {
        throw 'The Desktop-only shortcut selection was not preserved.'
    }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($desktopLink)
        try {
            if ($link.TargetPath -ine $exe) { throw 'The Desktop shortcut does not target the fixture.' }
        } finally { [void] [Runtime.InteropServices.Marshal]::ReleaseComObject($link) }
    } finally { [void] [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}

try {
    $previousUrl = "https://github.com/4ls4mi/super-booster/releases/download/v$previousVersion/SuperBooster-$previousVersion-windows-x64-setup.exe"
    Invoke-WebRequest -Uri $previousUrl -OutFile $priorInstaller -MaximumRedirection 3
    if ((Get-FileHash -LiteralPath $priorInstaller).Hash -cne $previousSha256) {
        throw 'The prior installer SHA-256 does not match the pinned release.'
    }
    $initialOptions = $silent + @('/SP-', '/TASKS=desktopicon', ('/DIR="{0}"' -f $installDir))
    $initialSetup = Start-Process -FilePath $priorInstaller -ArgumentList $initialOptions -WindowStyle Hidden -PassThru
    try { Wait-ForProcess $initialSetup 120 'Pinned baseline installer' }
    finally { $initialSetup.Dispose() }

    $baseline = Get-ItemProperty -LiteralPath $registry
    if ($baseline.DisplayVersion -cne $previousVersion -or $baseline.InstallLocation.TrimEnd('\') -ine $installDir) {
        throw 'The prior release did not register the expected fixture location.'
    }
    Assert-DesktopOnly

    # Disable engine, hotkeys and update traffic in the disposable runner installation.
    $settings = Join-Path $installDir 'booster_settings.json'
    $routing = Join-Path $installDir 'booster_audio_route.json'
    $update = Join-Path $installDir 'booster_update.ini'
    Set-Content -LiteralPath $settings -Value '{"volume":173,"engine_active":false,"hotkeys_enabled":false}' -Encoding ascii
    Set-Content -LiteralPath $routing -Value '{"upgrade_fixture":true}' -Encoding ascii
    Set-Content -LiteralPath $update -Value '[General]', 'automatic=false', 'notificationMode=quiet' -Encoding ascii
    $dataDigests = @{}
    foreach ($file in $settings, $routing, $update) {
        $dataDigests[$file] = (Get-FileHash -LiteralPath $file).Hash
    }

    $env:QT_QUICK_BACKEND = 'software'
    $oldProcess = Start-Process -FilePath $exe -ArgumentList '--minimized' -WorkingDirectory $installDir -WindowStyle Hidden -PassThru
    if ($oldProcess.HasExited -or $oldProcess.MainModule.FileName -ine $exe) {
        throw 'The prior-release fixture process could not be started.'
    }
    $candidateCopy = Join-Path $scratch.FullName $candidate.Name
    $helperCopy = Join-Path $scratch.FullName 'super_booster_update_helper.exe'
    Copy-Item -LiteralPath $candidate.FullName -Destination $candidateCopy
    Copy-Item -LiteralPath $sourceHelper -Destination $helperCopy
    $candidateDigest = (Get-FileHash -LiteralPath $candidate.FullName).Hash.ToLowerInvariant()
    $handoffArgs = @([string] $oldProcess.Id, ('"{0}"' -f $installDir),
        ('"{0}"' -f $candidateCopy), $candidateDigest, [string] $candidate.Length, $expectedVersion)
    $startHelperOptions = @{
        FilePath = $helperCopy
        ArgumentList = $handoffArgs
        WorkingDirectory = $scratch.FullName
        WindowStyle = 'Hidden'
        PassThru = $true
    }
    $handoff = Start-Process @startHelperOptions

    Wait-ForCondition {
        if ($handoff.HasExited -or $oldProcess.HasExited -or (Test-Path -LiteralPath $errorMarker)) {
            throw 'The handoff or prior-release process stopped before readiness.'
        }
        Test-Path -LiteralPath $ready -PathType Leaf
    } 30 'The helper did not signal readiness.'
    if ((Test-Path -LiteralPath $setupLog) -or
        (Get-ItemPropertyValue -LiteralPath $registry -Name DisplayVersion) -cne $previousVersion) {
        throw 'Setup began before the fixture had confirmed and exited.'
    }
    Set-Content -LiteralPath $confirmed -Value 'confirmed' -NoNewline -Encoding ascii
    # The fixture exposes no noninteractive Quit command. Stop only its exact process handle.
    $oldProcess.Kill()
    if (-not $oldProcess.WaitForExit(10000)) { throw 'The prior-release fixture did not exit.' }
    Wait-ForProcess $handoff 180 'Verified update helper'

    $updated = Get-ItemProperty -LiteralPath $registry
    if ($updated.DisplayVersion -cne $expectedVersion -or $updated.InstallLocation.TrimEnd('\') -ine $installDir) {
        throw 'The handoff updated the wrong version or installation location.'
    }
    if ((Get-FileHash -LiteralPath $exe).Hash -cne $exeDigest) {
        throw 'The installed application differs from the candidate staging payload.'
    }
    Assert-DesktopOnly
    foreach ($file in $dataDigests.Keys) {
        if ((Get-FileHash -LiteralPath $file).Hash -cne $dataDigests[$file]) {
            throw 'The upgrade did not preserve settings or audio routing data.'
        }
    }
    Wait-ForCondition { [bool](Get-FixtureProcesses | Select-Object -First 1) } 15 'The helper did not relaunch the installed application.'
    'Passed pinned baseline upgrade, verified handoff, new executable, relaunch, and preserved shortcut and settings.'
} catch {
    if (Test-Path -LiteralPath $errorMarker) { Write-Host (Get-Content -LiteralPath $errorMarker -Raw) }
    if (Test-Path -LiteralPath $setupLog) { Get-Content -LiteralPath $setupLog -Tail 12 | Write-Host }
    throw
} finally {
    if ($handoff) {
        if (-not $handoff.HasExited) { $handoff.Kill($true); [void] $handoff.WaitForExit(10000) }
        $handoff.Dispose()
    }
    if ($oldProcess) { $oldProcess.Dispose() }
    foreach ($process in (Get-FixtureProcesses)) {
        try {
            if (-not $process.HasExited) { $process.Kill(); [void] $process.WaitForExit(10000) }
        } finally { $process.Dispose() }
    }
    $env:QT_QUICK_BACKEND = $previousQtBackend

    $entry = Get-ItemProperty -LiteralPath $registry -ErrorAction SilentlyContinue
    if ($entry -and $entry.InstallLocation.TrimEnd('\') -ieq $installDir -and
        [string] $entry.UninstallString -match '^"([^"]+)"') {
        $uninstaller = $Matches[1]
        if ([IO.Path]::GetDirectoryName($uninstaller) -ine $installDir) {
            throw 'The registered uninstaller is outside the isolated fixture.'
        }
        $options = $silent + @('/PURGEDATA', ('/LOG="{0}"' -f $cleanupLog))
        $cleanup = Start-Process -FilePath $uninstaller -ArgumentList $options -WindowStyle Hidden -PassThru
        try { Wait-ForProcess $cleanup 120 'Fixture uninstaller' }
        finally { $cleanup.Dispose() }
        Wait-ForCondition {
            (Test-Path -LiteralPath $cleanupLog) -and
            (Select-String -LiteralPath $cleanupLog -SimpleMatch 'Super Booster uninstall completed.' -Quiet)
        } 20 'The fixture uninstaller did not finish cleaning up.'
        foreach ($path in $registry, $startLink, $desktopLink, $exe) {
            if (Test-Path -LiteralPath $path) { throw 'The fixture uninstaller left registration, a shortcut, or the app.' }
        }
    }
}
