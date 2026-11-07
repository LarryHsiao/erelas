; Erelas - Inno Setup script
; Ported from Orthanc's installer/orthanc.iss.
; Compile from the repo root with:
;   ISCC.exe installer\erelas.iss
; scripts\build_windows.ps1 does this, passing the pubspec version.
; Output lands in build\installer\.

#define MyAppName        "Erelas"
; Supplied by the build script via ISCC /DMyAppVersion=<pubspec x.y.z>.
; The literal below is only a fallback for a bare local compile.
#ifndef MyAppVersion
  #define MyAppVersion   "1.0.0"
#endif
#define MyAppPublisher   "Larry Hsiao"
#define MyAppURL         "https://github.com/LarryHsiao/erelas"
#define MyAppExeName     "erelas.exe"
#define MyAppSourceDir   "..\build\windows\x64\runner\Release"
#define MyAppOutputDir   "..\build\installer"

[Setup]
; A fixed GUID - keep it constant across versions so an upgrade replaces the
; installed copy. It is Erelas's own; do not reuse another product's.
AppId={{2602118B-C475-4937-B23E-86A9A53D131B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyAppOutputDir}
OutputBaseFilename=erelas-setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\*.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\data\*";           DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}";              Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}";        Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
