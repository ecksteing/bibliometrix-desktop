; installer_config.iss

[Setup]
AppName=Bibliometrix Desktop
AppVersion=1.0.0
DefaultDirName={autopf}\Bibliometrix Desktop
DefaultGroupName=Bibliometrix Desktop
OutputDir=Output
OutputBaseFilename=BibliometrixSetup
Compression=lzma
SolidCompression=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "run_bibliometrix.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "launch_app.R"; DestDir: "{app}"; Flags: ignoreversion
Source: "R-Portable\*"; DestDir: "{app}\R-Portable"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Bibliometrix Desktop"; Filename: "{app}\run_bibliometrix.exe"
Name: "{autodesktop}\Bibliometrix Desktop"; Filename: "{app}\run_bibliometrix.exe"; Tasks: desktopicon