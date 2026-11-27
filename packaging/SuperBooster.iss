#ifndef AppName
  #define AppName "Super Booster"
#endif
#ifndef AppId
  #define AppId "2FB21D94-87B2-432C-A6D9-6359C478234D"
#endif
#define AppExecutable "super_booster.exe"
#define OwnerRegistryKey "Software\SuperBooster\Installer\" + AppId

#ifndef AppVersion
  #error AppVersion is required. Use Build-Installer.ps1 or pass /DAppVersion.
#endif
#ifndef StageDirectory
  #error StageDirectory is required. Use Build-Installer.ps1 or pass /DStageDirectory.
#endif

[Setup]
AppId={{{#AppId}}
AppName={#AppName}
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
ShowLanguageDialog=yes
UsePreviousTasks=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
SetupIconFile=..\assets\super-booster.ico
UninstallDisplayIcon={app}\{#AppExecutable}
OutputBaseFilename=SuperBooster-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
RestartApplications=no

[Messages]
en.WelcomeLabel2=This installs {#AppName} for your Windows account.%n%nThe app uses Qt under the GNU Lesser General Public License version 3. License texts, notices, and source links are included in the installed third-party folder.

[CustomMessages]
CreateStartMenuShortcut=Create a Start menu shortcut
ShowTaskbarPinHelp=Open the app so I can pin it to the taskbar
TaskbarPinHelp=Right-click the running app's icon on the Windows taskbar and choose Pin to taskbar.
RemoveSettingsPrompt=Also remove this installation's saved settings and audio routing data, and delete its folder if it is empty? This cannot be undone.
RemoveSettingsIncomplete=Some settings could not be removed safely and were kept.

#include "InstallerLanguages.iss"

[Tasks]
Name: "startmenu"; Description: "{cm:CreateStartMenuShortcut}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked
Name: "taskbarhelp"; Description: "{cm:ShowTaskbarPinHelp}"; Flags: unchecked checkedonce

[Files]
Source: "{#StageDirectory}\*"; DestDir: "{app}"; Excludes: "booster_settings.json,booster_audio_route.json,booster_audio_route.json.lock"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"; Tasks: startmenu
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "{#OwnerRegistryKey}"; ValueType: string; ValueName: "OwnedDirectory"; ValueData: "{app}"; Flags: uninsdeletevalue uninsdeletekeyifempty; Check: CanMarkOwnedDirectory

[Run]
Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"; Tasks: taskbarhelp; Flags: nowait runasoriginaluser skipifsilent; AfterInstall: ShowTaskbarPinInstruction

[Code]
const
  OwnerRegistryKey = '{#OwnerRegistryKey}';
  UninstallRegistryKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{#AppId}}_is1';
  InvalidFileAttributes = $FFFFFFFF;
  ReparsePointAttribute = $400;
  FixedDriveType = 3;
  SettingsFile = 'booster_settings.json';
  RouteFile = 'booster_audio_route.json';
  RouteLockFile = 'booster_audio_route.json.lock';

var
  MarkOwnedDirectory, PurgeData: Boolean;

function WindowsGetFileAttributes(const Path: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function WindowsGetDriveType(const Drive: String): Cardinal;
  external 'GetDriveTypeW@kernel32.dll stdcall';

function IsWithinDirectory(const Path, Parent: String): Boolean;
begin
  Result := PathSame(Path, Parent) or PathStartsWith(Path, AddBackslash(Parent), True);
end;

function IsSafeAppDirectory(const Dir: String; AllowMissing: Boolean): Boolean;
var
  Current, DriveRoot, Parent: String;
  Attributes: Cardinal;
begin
  Result := False;
  Current := RemoveBackslashUnlessRoot(PathNormalizeSlashes(Dir));
  DriveRoot := AddBackslash(ExtractFileDrive(Current));
  if (Length(DriveRoot) <> 3) or (DriveRoot[2] <> ':') or
     not PathStartsWith(Current, DriveRoot, True) or PathSame(Current, DriveRoot) or
     not PathSame(Current, ExpandFileName(Current)) then Exit;
  if WindowsGetDriveType(DriveRoot) <> FixedDriveType then Exit;

  if PathSame(Current, GetEnv('USERPROFILE')) or
     PathSame(Current, ExpandConstant('{localappdata}')) or
     PathSame(Current, ExpandConstant('{localappdata}\Programs')) or
     PathSame(Current, ExpandConstant('{userappdata}')) or
     PathSame(Current, ExpandConstant('{userdocs}')) or
     PathSame(Current, ExpandConstant('{userdesktop}')) or
     IsWithinDirectory(Current, ExpandConstant('{win}')) or
     IsWithinDirectory(Current, ExpandConstant('{commonappdata}')) or
     IsWithinDirectory(Current, ExpandConstant('{commonpf64}')) or
     IsWithinDirectory(Current, ExpandConstant('{commonpf32}')) then Exit;

  while not PathSame(Current, DriveRoot) do begin
    Attributes := WindowsGetFileAttributes(PathConvertNormalToSuper(Current));
    if Attributes = InvalidFileAttributes then begin
      if not AllowMissing then Exit;
    end else if ((Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or
                ((Attributes and ReparsePointAttribute) <> 0) then Exit;
    Parent := ExtractFileDir(Current);
    if (Parent = '') or PathSame(Current, Parent) then Exit;
    Current := Parent;
  end;
  Result := True;
end;

function IsKnownDataFile(const Name: String): Boolean;
begin
  Result := SameText(Name, SettingsFile) or SameText(Name, RouteFile) or SameText(Name, RouteLockFile);
end;

function DirectoryContainsOnlyKnownData(const Dir: String): Boolean;
var
  Entry: TFindRec;
begin
  Result := not FileOrDirExists(Dir);
  if Result then Exit;
  if not FindFirst(AddBackslash(Dir) + '*', Entry) then Exit;
  try
    repeat
      if (Entry.Name <> '.') and (Entry.Name <> '..') and
         (not IsKnownDataFile(Entry.Name) or
          ((Entry.Attributes and (FILE_ATTRIBUTE_DIRECTORY or ReparsePointAttribute)) <> 0)) then Exit;
    until not FindNext(Entry);
    Result := True;
  finally
    FindClose(Entry);
  end;
end;

function HasOwnershipRecord(const Dir: String): Boolean;
var
  RecordedDir: String;
begin
  Result := RegQueryStringValue(HKCU, OwnerRegistryKey, 'OwnedDirectory', RecordedDir) and
    PathSame(RemoveBackslashUnlessRoot(RecordedDir), RemoveBackslashUnlessRoot(Dir));
end;

function IsRegisteredDefaultDirectory(const Dir: String): Boolean;
var
  RecordedDir: String;
begin
  // Upgrade the original installer, which tracked its default directory without an ownership record.
  Result := PathSame(Dir, ExpandConstant('{localappdata}\Programs\{#AppName}')) and
    RegQueryStringValue(HKCU, UninstallRegistryKey, 'InstallLocation', RecordedDir) and
    PathSame(RemoveBackslashUnlessRoot(RecordedDir), RemoveBackslashUnlessRoot(Dir));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Dir: String;
begin
  if CurStep <> ssInstall then Exit;
  Log('Super Booster installer language: ' + ActiveLanguage);
  Dir := ExpandConstant('{app}');
  MarkOwnedDirectory := IsSafeAppDirectory(Dir, True) and
    (HasOwnershipRecord(Dir) or IsRegisteredDefaultDirectory(Dir) or DirectoryContainsOnlyKnownData(Dir));
end;

function CanMarkOwnedDirectory: Boolean;
begin
  Result := MarkOwnedDirectory and IsSafeAppDirectory(ExpandConstant('{app}'), False);
end;

procedure ShowTaskbarPinInstruction;
begin
  SuppressibleMsgBox(CustomMessage('TaskbarPinHelp'), mbInformation, MB_OK, IDOK);
end;

function HasPurgeArgument: Boolean;
var
  Index: Integer;
begin
  Result := True;
  for Index := 1 to ParamCount do
    if SameText(ParamStr(Index), '/PURGEDATA') then Exit;
  Result := False;
end;

function ShouldPurgeData(const Dir: String): Boolean;
begin
  Result := False;
  if not IsSafeAppDirectory(Dir, False) or not HasOwnershipRecord(Dir) then Exit;
  if UninstallSilent then begin
    Result := HasPurgeArgument;
    Exit;
  end;
  if FileOrDirExists(PathCombine(Dir, SettingsFile)) or
     FileOrDirExists(PathCombine(Dir, RouteFile)) or
     FileOrDirExists(PathCombine(Dir, RouteLockFile)) then
    Result := SuppressibleMsgBox(CustomMessage('RemoveSettingsPrompt'), mbConfirmation,
      MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
end;

function RemoveKnownDataFile(const Dir, Name: String): Boolean;
var
  Path: String;
  Attributes: Cardinal;
begin
  Result := False;
  if not IsSafeAppDirectory(Dir, False) then Exit;
  Path := PathCombine(Dir, Name);
  Attributes := WindowsGetFileAttributes(PathConvertNormalToSuper(Path));
  if Attributes = InvalidFileAttributes then
    Result := not FileOrDirExists(Path)
  else if (Attributes and (FILE_ATTRIBUTE_DIRECTORY or ReparsePointAttribute)) = 0 then
    Result := DeleteFile(Path);
end;

procedure RemoveOwnedAppData(const Dir: String);
var
  RemovedSettings, RemovedRoute, RemovedLock: Boolean;
begin
  if not DirExists(Dir) then Exit;
  RemovedSettings := RemoveKnownDataFile(Dir, SettingsFile);
  RemovedRoute := RemoveKnownDataFile(Dir, RouteFile);
  RemovedLock := RemoveKnownDataFile(Dir, RouteLockFile);
  if not RemovedSettings or not RemovedRoute or not RemovedLock then begin
    Log('Some Super Booster settings could not be removed safely and were kept.');
    if not UninstallSilent then
      SuppressibleMsgBox(CustomMessage('RemoveSettingsIncomplete'), mbInformation, MB_OK, IDOK);
  end;
  // RemoveDir removes an empty directory only; unrelated content remains in place.
  if IsSafeAppDirectory(Dir, False) then RemoveDir(Dir);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  StartupCommand, InstalledCommand, Dir: String;
begin
  Dir := ExpandConstant('{app}');
  if CurUninstallStep = usUninstall then
    PurgeData := ShouldPurgeData(Dir);
  if CurUninstallStep <> usPostUninstall then Exit;

  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
    'SuperBoosterAudio', StartupCommand) then begin
    StringChangeEx(StartupCommand, '/', '\', True);
    InstalledCommand := '"' + PathCombine(Dir, '{#AppExecutable}') + '" --minimized';
    if CompareText(StartupCommand, InstalledCommand) = 0 then
      RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
        'SuperBoosterAudio');
  end;
  if PurgeData then RemoveOwnedAppData(Dir);
end;
