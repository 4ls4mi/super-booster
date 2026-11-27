#define AppName "Super Booster"
#define AppExecutable "super_booster.exe"

#ifndef AppVersion
  #error AppVersion is required. Use Build-Installer.ps1 or pass /DAppVersion.
#endif
#ifndef StageDirectory
  #error StageDirectory is required. Use Build-Installer.ps1 or pass /DStageDirectory.
#endif

[Setup]
AppId={{2FB21D94-87B2-432C-A6D9-6359C478234D}
AppName={#AppName}
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
UninstallDisplayIcon={app}\{#AppExecutable}
OutputBaseFilename=SuperBooster-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
RestartApplications=no

[Messages]
WelcomeLabel2=This installs Super Booster for your Windows account.%n%nSuper Booster uses Qt under the GNU Lesser General Public License version 3. License texts, notices, and source links are included in the installed third-party folder.

[Files]
Source: "{#StageDirectory}\*"; DestDir: "{app}"; Excludes: "booster_settings.json,booster_audio_route.json,booster_audio_route.json.lock"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  StartupCommand, InstalledCommand: String;
begin
  // Leave another copy's startup entry and the user's saved audio settings intact.
  if (CurUninstallStep = usPostUninstall) and
     RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
       'SuperBoosterAudio', StartupCommand) then
  begin
    StringChangeEx(StartupCommand, '/', '\', True);
    InstalledCommand := '"' + ExpandConstant('{app}\{#AppExecutable}') + '" --minimized';
    if CompareText(StartupCommand, InstalledCommand) = 0 then
      RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
        'SuperBoosterAudio');
  end;
end;
