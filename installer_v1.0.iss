; Script Inno Setup para Hemacias Analyzer v1.0
; Maurinsoft

#define MyAppName "Hemacias Analyzer"
#define MyAppVersion "1.0"
#define MyAppPublisher "Maurinsoft"
#define MyAppURL "https://maurinsoft.com.br"
#define MyAppExeName "hemacias_analyzer.exe"

[Setup]
AppId={{A91C3E20-5B1D-4890-B8E2-9876543210FE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Maurinsoft\HemaciasAnalyzer
DefaultGroupName=Maurinsoft\Hemacias Analyzer
AllowNoIcons=yes
OutputDir=D:\projetos\maurinsoft\hemacias\bin
OutputBaseFilename=HemaciasAnalyzer_Setup_v1.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "D:\projetos\maurinsoft\hemacias\lazarus\hemacias_analyzer\hemacias_analyzer.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\*"; DestDir: "{app}\models"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "D:\projetos\maurinsoft\hemacias\python\camera_capture.py"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\lazarus\hemacias_analyzer\README.md"; DestDir: "{app}"; DestName: "README_Lazarus.md"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
