#define MyAppName "핑크폰 CRM"
#define MyAppVersion "1.0.11"
#define MyAppPublisher "Pink Phone"
#define MyAppExeName "핑크폰 CRM.exe"
#define MyBuildExeName "crm_app.exe"
#define MyBuildDir "build\windows\x64\runner\Release"
#define InstallerPassword "123456"

[Setup]
AppId={{A1B2C3D4-E5F6-47A8-9B10-112233445566}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename=pinkphone-crm-setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
CloseApplications=yes
RestartApplications=no
CloseApplicationsFilter=*.exe,*.dll
Password={#InstallerPassword}
Encryption=yes
SetupIconFile=windows\runner\resources\installer_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면 아이콘 만들기"; GroupDescription: "바로가기:"; Flags: unchecked

[Files]
Source: "{#MyBuildDir}\{#MyBuildExeName}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Excludes: "{#MyBuildExeName}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autoprograms}\제거 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{#MyAppName} 실행"; Flags: nowait postinstall

[InstallDelete]
Type: files; Name: "{app}\crm_app.exe"

[UninstallDelete]
Type: files; Name: "{app}\*.log"
Type: filesandordirs; Name: "{app}\cache"
