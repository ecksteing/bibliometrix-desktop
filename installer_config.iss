; installer_config.iss
; Builds the Windows installer for Bibliometrix Desktop.
; Prerequisites: PyInstaller --onedir output staged as run_bibliometrix.exe +
; _internal\ at the repo root, and R-Portable prepared with
; scripts/bake_packages.R (binary packages preinstalled).

; --- Read version dynamically from version.txt ---
#define VerFile FileOpen("version.txt")
#define MyAppVersion FileRead(VerFile)
#expr FileClose(VerFile)

#define MyAppName "Bibliometrix Desktop"
#define MyAppPublisher "Gary Eckstein"
#define MyAppURL "https://github.com/ecksteing/bibliometrix-desktop"
#define MyAppExeName "run_bibliometrix.exe"

[Setup]
; IMPORTANT: keep this GUID stable across releases so upgrades/uninstall work.
AppId={{44CCE842-B1D9-4288-AD05-6C05DB32D0CE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=LICENSE
OutputDir=Output
OutputBaseFilename=BibliometrixSetup_{#MyAppVersion}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
CloseApplications=force
RestartIfNeededByRun=no
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "run_bibliometrix.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "_internal\*"; DestDir: "{app}\_internal"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "launch_app.R"; DestDir: "{app}"; Flags: ignoreversion
Source: "loading.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "stop_bibliometrix.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "version.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "R-Portable\*"; DestDir: "{app}\R-Portable"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

; Remove the entire install folder, including runtime data Inno did not install
; (CRAN updates in R_library, launcher.log, and any other leftovers).
[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
procedure StopAppProcesses();
var
  ResultCode: Integer;
  ScriptPath: String;
begin
  ScriptPath := ExpandConstant('{app}\stop_bibliometrix.ps1');
  if FileExists(ScriptPath) then
  begin
    Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode
    );
  end;
end;

function InitializeUninstall(): Boolean;
begin
  { Must run before files are deleted, while stop_bibliometrix.ps1 still exists. }
  StopAppProcesses();
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  { Stop processes on upgrade/reinstall so files can be replaced. }
  StopAppProcesses();
  Result := '';
end;
