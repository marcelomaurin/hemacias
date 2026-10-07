; Script Inno Setup para Hemacias Analyzer v1.2
; Maurinsoft

#define MyAppName "Hemacias Analyzer"
#define MyAppVersion "1.2"
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
OutputBaseFilename=HemaciasAnalyzer_Setup_v1.2
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Executavel principal do Lazarus
Source: "D:\projetos\maurinsoft\hemacias\lazarus\hemacias_analyzer\hemacias_analyzer.exe"; DestDir: "{app}"; Flags: ignoreversion

; Modelos de IA especializados para analise sanguinea
Source: "D:\projetos\maurinsoft\hemacias\models\blood-seg-v1.pt"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\best.pt"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\blood-cell-bccd-yolov8s.pt"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\blood-cell-bccd-yolov8n.pt"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\blood-seg-v1.onnx"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\yolo11n-seg.pt"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\yolo11n.pt"; DestDir: "{app}\models"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\models\README.md"; DestDir: "{app}\models"; Flags: ignoreversion

; Scripts de camera e instalacao de dependencias
Source: "D:\projetos\maurinsoft\hemacias\python\camera_capture.py"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\instalar_dependencias.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\requirements.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\requirements-ml.txt"; DestDir: "{app}"; Flags: ignoreversion

; Documentacao
Source: "D:\projetos\maurinsoft\hemacias\lazarus\hemacias_analyzer\README.md"; DestDir: "{app}"; DestName: "README_Lazarus.md"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\hemacias\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Instalar Dependencias de IA e Camera (Python)"; Filename: "{app}\instalar_dependencias.bat"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\instalar_dependencias.bat"; Description: "Instalar/Atualizar dependências Python (OpenCV, NumPy, Ultralytics/YOLO)"; Flags: postinstall skipifsilent unchecked
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function IsPythonInstalled: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('cmd.exe', '/c python --version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if not Result then
    Result := Exec('cmd.exe', '/c py -3 --version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if not IsPythonInstalled then
    begin
      MsgBox('Aviso sobre dependencias do sistema:' + #13#10#13#10 +
             'O interpretador Python 3 nao foi detectado no PATH do Windows.' + #13#10#13#10 +
             'Para utilizar a captura de cameras via OpenCV e a inferencia de IA com modelos YOLO, ' +
             'instale o Python 3 (versao 3.10 ou superior) marcando "Add Python to PATH".' + #13#10#13#10 +
             'Um atalho chamado "Instalar Dependencias de IA e Camera (Python)" foi adicionado ao menu Iniciar.',
             mbInformation, MB_OK);
    end;
  end;
end;
