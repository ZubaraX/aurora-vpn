; Portable Inno Setup script — compiled in CI (paths are relative to this file).
; Version is passed by CI: ISCC /DMyAppVersion=1.1.1 windows\installer\aurora.iss
#ifndef MyAppVersion
  #define MyAppVersion "1.1.1"
#endif
#define MyAppName "Aurora VPN"
#define MyAppPublisher "Aurora"
#define MyAppExeName "aurora.exe"
#define RelDir SourcePath + "..\..\build\windows\x64\runner\Release"
#define IconFile SourcePath + "..\runner\resources\app_icon.ico"

[Setup]
AppId={{7F3A9C2E-1B4A-4E7D-9E7D-0A1B2C3D4E5F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Aurora
DefaultGroupName=Aurora VPN
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
OutputDir={#SourcePath}..\..\dist
OutputBaseFilename=Aurora-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#IconFile}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#RelDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
; The tunnel needs elevation — force aurora.exe to always run as administrator.
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"; \
  ValueType: string; ValueName: "{app}\{#MyAppExeName}"; ValueData: "~ RUNASADMIN"; \
  Flags: uninsdeletevalue

[Icons]
Name: "{group}\Aurora VPN"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,Aurora VPN}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Aurora VPN"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
