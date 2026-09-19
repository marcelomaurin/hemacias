unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, ComCtrls, fpjson, pythonconnector, yolodetect, chatgpt, hemacias_api;

type
  TClassSummary = record
    Code: string;
    DisplayName: string;
    Count: Integer;
    ConfidenceSum: Double;
  end;
  TClassSummaryArray = array of TClassSummary;

  TProtocolItem = record
    Code: string;
    Name: string;
    UnitName: string;
    Threshold: Double;
    AIEnabled: Boolean;
  end;
  TProtocolItemArray = array of TProtocolItem;

  { TfrmMain }

  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FConnector: TPythonConnector;
    FYolo: TYOLO;
    FChatGPT: TCHATGPT;
    FApi: THemaciasApiClient;
    FConfigJSON: TJSONObject;

    FTop: TPanel;
    FApiPanel: TPanel;
    FConfig: TPanel;
    FRight: TPanel;
    FBottom: TPanel;
    FImage: TImage;
    FGrid: TStringGrid;
    FMemo: TMemo;
    FStatus: TStatusBar;

    FBtnLoad: TButton;
    FBtnAnalyze: TButton;
    FBtnSend: TButton;
    FBtnExport: TButton;
    FBtnAIReport: TButton;
    FBtnModel: TButton;
    FBtnClear: TButton;
    FBtnConnect: TButton;
    FBtnBindSample: TButton;

    FEdImage: TEdit;
    FEdModel: TEdit;
    FEdConfidence: TEdit;
    FEdImageSize: TEdit;
    FEdDevice: TEdit;
    FEdApiURL: TEdit;
    FEdApiKey: TEdit;
    FEdPatientName: TEdit;
    FEdPatientExternal: TEdit;
    FEdSampleCode: TEdit;
    FCbProtocol: TComboBox;

    FOpenImage: TOpenDialog;
    FOpenModel: TOpenDialog;
    FSaveReport: TSaveDialog;

    FObjects: TYoloObjectArray;
    FSummaries: TClassSummaryArray;
    FProtocolItems: TProtocolItemArray;
    FCurrentImage: string;
    FLastDeterministicReport: string;
    FChatConfigured: Boolean;
    FPatientID: Int64;
    FSampleID: Int64;
    FProtocolID: Int64;
    FProtocolCode: string;
    FScaleLabel: string;
    FMagnification: Double;
    FModelID: Int64;
    FModelSHA256: string;
    FModelVersion: string;

    procedure BuildUI;
    procedure InitializeAI;
    procedure SetStatus(const AText: string);
    procedure Log(const AText: string);

    procedure LoadImageClick(Sender: TObject);
    procedure SelectModelClick(Sender: TObject);
    procedure AnalyzeClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure AIReportClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ConnectClick(Sender: TObject);
    procedure BindSampleClick(Sender: TObject);

    function ConfidenceValue: Double;
    function ImageSizeValue: Integer;
    function NormalizeClass(const AName: string): string;
    function DisplayClass(const ACode: string): string;
    function ColorForClass(const ACode: string): TColor;
    function ThresholdForClass(const ACode: string): Double;
    function IsClassEnabled(const ACode: string): Boolean;
    function ComputeFileSHA256(const AFileName: string): string;
    function VerifyConfiguredModel: Boolean;

    procedure BuildSummaries;
    procedure UpdateGrid;
    procedure DrawDetections;
    procedure BuildDeterministicReport;
    procedure PopulateProtocols(AConfig: TJSONObject);
    procedure ApplySampleConfig(AConfig: TJSONObject);
    procedure LoadProtocolItems(AProtocol: TJSONObject);

    function FindSummary(const ACode: string): Integer;
    procedure AddSummary(const ACode: string; AConfidence: Double);
    function BuildCountPayload: TJSONObject;

    procedure ExportJSON(const AFileName: string);
    procedure ExportCSV(const AFileName: string);
    procedure ExportText(const AFileName: string);
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

function ObjStr(AObj: TJSONObject; const AName, ADefault: string): string;
var
  D: TJSONData;
begin
  Result := ADefault;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType <> jtNull) then
    Result := D.AsString;
end;

function ObjInt(AObj: TJSONObject; const AName: string; ADefault: Int64 = 0): Int64;
var
  D: TJSONData;
begin
  Result := ADefault;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType <> jtNull) then
    Result := StrToInt64Def(D.AsString, ADefault);
end;

function ObjFloat(AObj: TJSONObject; const AName: string; ADefault: Double = 0): Double;
var
  D: TJSONData;
  FS: TFormatSettings;
begin
  Result := ADefault;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D = nil) or (D.JSONType = jtNull) then Exit;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := StrToFloatDef(StringReplace(D.AsString, ',', '.', [rfReplaceAll]), ADefault, FS);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'Analisador de Lâminas - Lazarus AI Suite';
  FConfigJSON := nil;
  FApi := nil;
  FPatientID := 0;
  FSampleID := 0;
  BuildUI;
  InitializeAI;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FConfigJSON.Free;
  FApi.Free;
  if Assigned(FConnector) and FConnector.Active then
    FConnector.Active := False;
end;

procedure TfrmMain.BuildUI;
var
  L: TLabel;
begin
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.Height := 54;
  FTop.BevelOuter := bvNone;

  FBtnLoad := TButton.Create(Self);
  FBtnLoad.Parent := FTop;
  FBtnLoad.SetBounds(10, 10, 120, 32);
  FBtnLoad.Caption := 'Carregar lâmina';
  FBtnLoad.OnClick := @LoadImageClick;

  FBtnAnalyze := TButton.Create(Self);
  FBtnAnalyze.Parent := FTop;
  FBtnAnalyze.SetBounds(140, 10, 95, 32);
  FBtnAnalyze.Caption := 'Analisar';
  FBtnAnalyze.OnClick := @AnalyzeClick;

  FBtnSend := TButton.Create(Self);
  FBtnSend.Parent := FTop;
  FBtnSend.SetBounds(245, 10, 115, 32);
  FBtnSend.Caption := 'Enviar campo';
  FBtnSend.OnClick := @SendClick;
  FBtnSend.Enabled := False;

  FBtnExport := TButton.Create(Self);
  FBtnExport.Parent := FTop;
  FBtnExport.SetBounds(370, 10, 115, 32);
  FBtnExport.Caption := 'Emitir resultado';
  FBtnExport.OnClick := @ExportClick;
  FBtnExport.Enabled := False;

  FBtnAIReport := TButton.Create(Self);
  FBtnAIReport.Parent := FTop;
  FBtnAIReport.SetBounds(495, 10, 125, 32);
  FBtnAIReport.Caption := 'Parecer com IA';
  FBtnAIReport.OnClick := @AIReportClick;
  FBtnAIReport.Enabled := False;

  FBtnClear := TButton.Create(Self);
  FBtnClear.Parent := FTop;
  FBtnClear.SetBounds(630, 10, 80, 32);
  FBtnClear.Caption := 'Limpar';
  FBtnClear.OnClick := @ClearClick;

  FApiPanel := TPanel.Create(Self);
  FApiPanel.Parent := Self;
  FApiPanel.Align := alTop;
  FApiPanel.Height := 122;
  FApiPanel.BevelOuter := bvLowered;

  L := TLabel.Create(Self); L.Parent := FApiPanel;
  L.SetBounds(10, 8, 55, 20); L.Caption := 'API URL:';
  FEdApiURL := TEdit.Create(Self); FEdApiURL.Parent := FApiPanel;
  FEdApiURL.SetBounds(70, 5, 365, 27);
  FEdApiURL.Text := '';

  L := TLabel.Create(Self); L.Parent := FApiPanel;
  L.SetBounds(450, 8, 55, 20); L.Caption := 'API key:';
  FEdApiKey := TEdit.Create(Self); FEdApiKey.Parent := FApiPanel;
  FEdApiKey.SetBounds(510, 5, 255, 27);
  FEdApiKey.PasswordChar := '*';

  FBtnConnect := TButton.Create(Self); FBtnConnect.Parent := FApiPanel;
  FBtnConnect.SetBounds(775, 4, 100, 30);
  FBtnConnect.Caption := 'Conectar';
  FBtnConnect.OnClick := @ConnectClick;

  L := TLabel.Create(Self); L.Parent := FApiPanel;
  L.SetBounds(10, 47, 60, 20); L.Caption := 'Paciente:';
  FEdPatientName := TEdit.Create(Self); FEdPatientName.Parent := FApiPanel;
  FEdPatientName.SetBounds(70, 43, 250, 27);

  L := TLabel.Create(Self); L.Parent := FApiPanel;
  L.SetBounds(330, 47, 65, 20); L.Caption := 'ID externo:';
  FEdPatientExternal := TEdit.Create(Self); FEdPatientExternal.Parent := FApiPanel;
  FEdPatientExternal.SetBounds(400, 43, 150, 27);

  L := TLabel.Create(Self); L.Parent := FApiPanel;
  L.SetBounds(565, 47, 60, 20); L.Caption := 'Amostra:';
  FEdSampleCode := TEdit.Create(Self); FEdSampleCode.Parent := FApiPanel;
  FEdSampleCode.SetBounds(625, 43, 140, 27);

  L := TLabel.Create(Self); L.Parent := FApiPanel;
  L.SetBounds(10, 85, 60, 20); L.Caption := 'Protocolo:';
  FCbProtocol := TComboBox.Create(Self); FCbProtocol.Parent := FApiPanel;
  FCbProtocol.SetBounds(70, 81, 300, 27);
  FCbProtocol.Style := csDropDownList;

  FBtnBindSample := TButton.Create(Self); FBtnBindSample.Parent := FApiPanel;
  FBtnBindSample.SetBounds(385, 79, 165, 31);
  FBtnBindSample.Caption := 'Vincular paciente/amostra';
  FBtnBindSample.OnClick := @BindSampleClick;
  FBtnBindSample.Enabled := False;

  FConfig := TPanel.Create(Self);
  FConfig.Parent := Self;
  FConfig.Align := alTop;
  FConfig.Height := 88;
  FConfig.BevelOuter := bvLowered;

  L := TLabel.Create(Self); L.Parent := FConfig;
  L.SetBounds(10, 8, 70, 20); L.Caption := 'Imagem:';
  FEdImage := TEdit.Create(Self); FEdImage.Parent := FConfig;
  FEdImage.SetBounds(78, 5, 510, 27); FEdImage.ReadOnly := True;

  L := TLabel.Create(Self); L.Parent := FConfig;
  L.SetBounds(10, 45, 60, 20); L.Caption := 'Modelo:';
  FEdModel := TEdit.Create(Self); FEdModel.Parent := FConfig;
  FEdModel.SetBounds(78, 42, 420, 27);
  FEdModel.Text := 'models' + PathDelim + 'blood-seg-v1.pt';

  FBtnModel := TButton.Create(Self); FBtnModel.Parent := FConfig;
  FBtnModel.SetBounds(505, 40, 83, 30);
  FBtnModel.Caption := 'Selecionar'; FBtnModel.OnClick := @SelectModelClick;

  L := TLabel.Create(Self); L.Parent := FConfig;
  L.SetBounds(610, 8, 73, 20); L.Caption := 'Confiança:';
  FEdConfidence := TEdit.Create(Self); FEdConfidence.Parent := FConfig;
  FEdConfidence.SetBounds(685, 5, 70, 27); FEdConfidence.Text := '0.25';

  L := TLabel.Create(Self); L.Parent := FConfig;
  L.SetBounds(775, 8, 47, 20); L.Caption := 'imgsz:';
  FEdImageSize := TEdit.Create(Self); FEdImageSize.Parent := FConfig;
  FEdImageSize.SetBounds(825, 5, 70, 27); FEdImageSize.Text := '1024';

  L := TLabel.Create(Self); L.Parent := FConfig;
  L.SetBounds(610, 45, 70, 20); L.Caption := 'Device:';
  FEdDevice := TEdit.Create(Self); FEdDevice.Parent := FConfig;
  FEdDevice.SetBounds(685, 42, 210, 27);
  FEdDevice.Hint := 'Vazio = automático; exemplos: 0, cpu';
  FEdDevice.ShowHint := True;

  FRight := TPanel.Create(Self);
  FRight.Parent := Self;
  FRight.Align := alRight;
  FRight.Width := 385;
  FRight.Caption := '';
  FRight.BevelOuter := bvLowered;

  L := TLabel.Create(Self); L.Parent := FRight;
  L.SetBounds(10, 10, 260, 22); L.Caption := 'Resultado da contagem';
  L.Font.Style := [fsBold]; L.Font.Size := 12;

  FGrid := TStringGrid.Create(Self); FGrid.Parent := FRight;
  FGrid.SetBounds(8, 40, 368, 250);
  FGrid.ColCount := 3; FGrid.RowCount := 2; FGrid.FixedRows := 1;
  FGrid.Cells[0,0] := 'Componente';
  FGrid.Cells[1,0] := 'Quantidade';
  FGrid.Cells[2,0] := 'Conf. média';
  FGrid.ColWidths[0] := 160; FGrid.ColWidths[1] := 80; FGrid.ColWidths[2] := 100;
  FGrid.Options := FGrid.Options - [goEditing];

  L := TLabel.Create(Self); L.Parent := FRight;
  L.SetBounds(10, 305, 300, 20); L.Caption := 'Relatório / observações';

  FMemo := TMemo.Create(Self); FMemo.Parent := FRight;
  FMemo.SetBounds(8, 330, 368, 300);
  FMemo.ScrollBars := ssAutoVertical; FMemo.WordWrap := True;

  FBottom := TPanel.Create(Self); FBottom.Parent := Self;
  FBottom.Align := alBottom; FBottom.Height := 28; FBottom.BevelOuter := bvNone;
  FStatus := TStatusBar.Create(Self); FStatus.Parent := FBottom;
  FStatus.Align := alClient; FStatus.SimplePanel := True;

  FImage := TImage.Create(Self); FImage.Parent := Self;
  FImage.Align := alClient; FImage.Center := True;
  FImage.Proportional := True; FImage.Stretch := True;

  FOpenImage := TOpenDialog.Create(Self);
  FOpenImage.Title := 'Selecionar imagem de lâmina';
  FOpenImage.Filter := 'Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.webp|Todos|*.*';

  FOpenModel := TOpenDialog.Create(Self);
  FOpenModel.Title := 'Selecionar modelo YOLO';
  FOpenModel.Filter := 'Modelo YOLO (*.pt)|*.pt|Todos|*.*';

  FSaveReport := TSaveDialog.Create(Self);
  FSaveReport.Title := 'Emitir resultado';
  FSaveReport.Filter := 'JSON (*.json)|*.json|CSV (*.csv)|*.csv|Texto (*.txt)|*.txt';
  FSaveReport.DefaultExt := 'json';
end;

procedure TfrmMain.InitializeAI;
begin
  FConnector := TPythonConnector.Create(Self);
  FConnector.ExecutionMode := pemProcess;

  FYolo := TYOLO.Create(Self);
  FYolo.PythonConnector := FConnector;
  FYolo.PreferProcessMode := True;

  FChatGPT := TCHATGPT.Create(Self);
  FChatConfigured := FChatGPT.LoadConfigFromAppData('ChatGPT');
  if FChatConfigured then
    Log('Configuração do TCHATGPT carregada.')
  else
    Log('TCHATGPT sem configuração salva; parecer textual indisponível.');

  SetStatus('Inicializando Python...');
  Application.ProcessMessages;
  try
    FConnector.Active := True;
    if FConnector.IsInitialized then
    begin
      SetStatus('Python ativo: ' + FConnector.Version);
      Log('Python inicializado em modo processo.');
    end
    else
    begin
      SetStatus('Python indisponível');
      Log('Falha ao iniciar Python: ' + FConnector.LastError);
    end;
  except
    on E: Exception do
    begin
      SetStatus('Erro ao inicializar Python');
      Log(E.Message);
    end;
  end;
end;

procedure TfrmMain.SetStatus(const AText: string);
begin
  FStatus.SimpleText := AText;
end;

procedure TfrmMain.Log(const AText: string);
begin
  FMemo.Lines.Add('[' + FormatDateTime('hh:nn:ss', Now) + '] ' + AText);
end;

procedure TfrmMain.ConnectClick(Sender: TObject);
var
  Cfg: TJSONObject;
begin
  FreeAndNil(FApi);
  FApi := THemaciasApiClient.Create(Trim(FEdApiURL.Text), Trim(FEdApiKey.Text));
  SetStatus('Consultando configuração do servidor...');
  Application.ProcessMessages;

  Cfg := FApi.GetConfig(0);
  if Cfg = nil then
  begin
    ShowMessage('Falha na API: ' + FApi.LastError);
    SetStatus('API indisponível.');
    Exit;
  end;

  FreeAndNil(FConfigJSON);
  FConfigJSON := Cfg;
  PopulateProtocols(FConfigJSON);
  FBtnBindSample.Enabled := FCbProtocol.Items.Count > 0;
  Log('API conectada. Protocolos carregados: ' + IntToStr(FCbProtocol.Items.Count));
  SetStatus('API conectada.');
end;

procedure TfrmMain.PopulateProtocols(AConfig: TJSONObject);
var
  D: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  P: TJSONObject;
begin
  FCbProtocol.Items.Clear;
  D := AConfig.Find('protocols');
  if not (D is TJSONArray) then Exit;
  Arr := TJSONArray(D);
  for I := 0 to Arr.Count - 1 do
  begin
    if Arr.Items[I] is TJSONObject then
    begin
      P := TJSONObject(Arr.Items[I]);
      FCbProtocol.Items.Add(ObjStr(P, 'name', ObjStr(P, 'code', 'Protocolo')));
    end;
  end;
  if FCbProtocol.Items.Count > 0 then FCbProtocol.ItemIndex := 0;
end;

procedure TfrmMain.BindSampleClick(Sender: TObject);
var
  D: TJSONData;
  Arr: TJSONArray;
  Proto: TJSONObject;
  ProtocolCode: string;
  Cfg: TJSONObject;
begin
  if FApi = nil then
  begin
    ShowMessage('Conecte à API primeiro.');
    Exit;
  end;
  if Trim(FEdPatientName.Text) = '' then
  begin
    ShowMessage('Informe o nome do paciente.');
    Exit;
  end;
  if Trim(FEdSampleCode.Text) = '' then
  begin
    ShowMessage('Informe o código da amostra.');
    Exit;
  end;
  if FCbProtocol.ItemIndex < 0 then
  begin
    ShowMessage('Selecione um protocolo.');
    Exit;
  end;

  D := FConfigJSON.Find('protocols');
  if not (D is TJSONArray) then Exit;
  Arr := TJSONArray(D);
  Proto := TJSONObject(Arr.Items[FCbProtocol.ItemIndex]);
  ProtocolCode := ObjStr(Proto, 'code', '');

  FPatientID := FApi.UpsertPatient(Trim(FEdPatientName.Text),
    Trim(FEdPatientExternal.Text));
  if FPatientID < 1 then
  begin
    ShowMessage('Falha ao vincular paciente: ' + FApi.LastError);
    Exit;
  end;

  FSampleID := FApi.CreateSample(FPatientID, Trim(FEdSampleCode.Text), ProtocolCode);
  if FSampleID < 1 then
  begin
    ShowMessage('Falha ao vincular amostra: ' + FApi.LastError);
    Exit;
  end;

  Cfg := FApi.GetConfig(FSampleID);
  if Cfg = nil then
  begin
    ShowMessage('Amostra criada, mas a configuração não pôde ser lida: ' + FApi.LastError);
    Exit;
  end;
  try
    ApplySampleConfig(Cfg);
  finally
    Cfg.Free;
  end;

  Log(Format('Paciente #%d / amostra #%d vinculados ao protocolo %s.',
    [FPatientID, FSampleID, FProtocolCode]));
  SetStatus('Amostra vinculada ao servidor.');
end;

procedure TfrmMain.ApplySampleConfig(AConfig: TJSONObject);
var
  SampleD, ProtocolsD: TJSONData;
  SampleObj, Proto: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  SampleProtocolID: Int64;
  MinThreshold: Double;
  LocalPath: string;
begin
  SampleD := AConfig.Find('sample');
  if not (SampleD is TJSONObject) then Exit;
  SampleObj := TJSONObject(SampleD);
  SampleProtocolID := ObjInt(SampleObj, 'protocol_id', 0);

  ProtocolsD := AConfig.Find('protocols');
  if not (ProtocolsD is TJSONArray) then Exit;
  Arr := TJSONArray(ProtocolsD);

  Proto := nil;
  for I := 0 to Arr.Count - 1 do
    if (Arr.Items[I] is TJSONObject) and
       (ObjInt(TJSONObject(Arr.Items[I]), 'id', 0) = SampleProtocolID) then
    begin
      Proto := TJSONObject(Arr.Items[I]);
      Break;
    end;

  if Proto = nil then Exit;

  FProtocolID := ObjInt(Proto, 'id', 0);
  FProtocolCode := ObjStr(Proto, 'code', '');
  FScaleLabel := ObjStr(Proto, 'default_scale_label', '');
  FMagnification := ObjFloat(Proto, 'default_magnification', 0);
  FModelID := ObjInt(Proto, 'default_model_id', 0);
  FModelSHA256 := LowerCase(ObjStr(Proto, 'model_sha256', ''));
  FModelVersion := ObjStr(Proto, 'model_version', '');

  LocalPath := ObjStr(Proto, 'model_path', '');
  if LocalPath <> '' then
  begin
    if (not FileExists(LocalPath)) and
       FileExists(ExtractFilePath(ParamStr(0)) + LocalPath) then
      LocalPath := ExtractFilePath(ParamStr(0)) + LocalPath;
    FEdModel.Text := LocalPath;
  end;

  if ObjInt(Proto, 'model_imgsz', 0) > 0 then
    FEdImageSize.Text := IntToStr(ObjInt(Proto, 'model_imgsz', 0));

  LoadProtocolItems(Proto);
  MinThreshold := 1.0;
  for I := 0 to High(FProtocolItems) do
    if FProtocolItems[I].AIEnabled and
       (FProtocolItems[I].Threshold < MinThreshold) then
      MinThreshold := FProtocolItems[I].Threshold;
  if MinThreshold <= 1.0 then
    FEdConfidence.Text := StringReplace(FormatFloat('0.000', MinThreshold), ',', '.', [rfReplaceAll]);

  if (FModelID > 0) and (not FileExists(FEdModel.Text)) then
    Log('Modelo do protocolo não existe localmente. Selecione o arquivo correspondente: ' +
      FEdModel.Text);

  Log('Configuração aplicada: protocolo=' + FProtocolCode +
    ', modelo=' + FModelVersion + ', itens=' + IntToStr(Length(FProtocolItems)));
end;

procedure TfrmMain.LoadProtocolItems(AProtocol: TJSONObject);
var
  D: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONObject;
begin
  SetLength(FProtocolItems, 0);
  D := AProtocol.Find('items');
  if not (D is TJSONArray) then Exit;
  Arr := TJSONArray(D);
  SetLength(FProtocolItems, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    Item := TJSONObject(Arr.Items[I]);
    FProtocolItems[I].Code := LowerCase(ObjStr(Item, 'code', ''));
    FProtocolItems[I].Name := ObjStr(Item, 'name', FProtocolItems[I].Code);
    FProtocolItems[I].UnitName := ObjStr(Item, 'default_unit', 'células/campo');
    FProtocolItems[I].Threshold := ObjFloat(Item, 'confidence_threshold', 0.25);
    FProtocolItems[I].AIEnabled := ObjInt(Item, 'ai_enabled', 0) <> 0;
  end;
end;

procedure TfrmMain.LoadImageClick(Sender: TObject);
begin
  if not FOpenImage.Execute then Exit;
  FCurrentImage := FOpenImage.FileName;
  FEdImage.Text := FCurrentImage;
  FImage.Picture.LoadFromFile(FCurrentImage);
  SetLength(FObjects, 0);
  SetLength(FSummaries, 0);
  UpdateGrid;
  FBtnExport.Enabled := False;
  FBtnAIReport.Enabled := False;
  FBtnSend.Enabled := False;
  FMemo.Clear;
  Log('Lâmina carregada: ' + FCurrentImage);
  SetStatus('Lâmina pronta para análise.');
end;

procedure TfrmMain.SelectModelClick(Sender: TObject);
begin
  if FOpenModel.Execute then
    FEdModel.Text := FOpenModel.FileName;
end;

function TfrmMain.ConfidenceValue: Double;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Result := StrToFloatDef(StringReplace(Trim(FEdConfidence.Text), ',', '.', [rfReplaceAll]), 0.25, FS);
  Result := EnsureRange(Result, 0.0, 1.0);
end;

function TfrmMain.ImageSizeValue: Integer;
begin
  Result := Max(0, StrToIntDef(Trim(FEdImageSize.Text), 1024));
end;

function TfrmMain.NormalizeClass(const AName: string): string;
var
  S: string;
begin
  S := LowerCase(Trim(AName));
  if (S = 'rbc') or (S = 'red blood cell') or (S = 'red_blood_cell') then Exit('hemacia');
  if (S = 'wbc') or (S = 'white blood cell') or (S = 'white_blood_cell') then Exit('leucocito');
  if S = 'platelet' then Exit('plaqueta');
  if S = 'artifact' then Exit('artefato');
  Result := S;
end;

function TfrmMain.DisplayClass(const ACode: string): string;
var
  I: Integer;
begin
  for I := 0 to High(FProtocolItems) do
    if FProtocolItems[I].Code = ACode then Exit(FProtocolItems[I].Name);
  if ACode = 'hemacia' then Exit('Hemácia');
  if ACode = 'leucocito' then Exit('Leucócito');
  if ACode = 'plaqueta' then Exit('Plaqueta');
  if ACode = 'artefato' then Exit('Artefato');
  if ACode = 'outro' then Exit('Outro');
  Result := ACode;
end;

function TfrmMain.ColorForClass(const ACode: string): TColor;
begin
  if ACode = 'hemacia' then Exit(clLime);
  if ACode = 'leucocito' then Exit(clBlue);
  if ACode = 'plaqueta' then Exit(clFuchsia);
  if ACode = 'artefato' then Exit(clRed);
  Result := clYellow;
end;

function TfrmMain.ThresholdForClass(const ACode: string): Double;
var
  I: Integer;
begin
  Result := ConfidenceValue;
  for I := 0 to High(FProtocolItems) do
    if FProtocolItems[I].Code = ACode then
      Exit(FProtocolItems[I].Threshold);
end;

function TfrmMain.IsClassEnabled(const ACode: string): Boolean;
var
  I: Integer;
begin
  if Length(FProtocolItems) = 0 then Exit(True);
  for I := 0 to High(FProtocolItems) do
    if FProtocolItems[I].Code = ACode then
      Exit(FProtocolItems[I].AIEnabled);
  Result := False;
end;

function TfrmMain.ComputeFileSHA256(const AFileName: string): string;
var
  P: string;
begin
  Result := '';
  if (not FConnector.IsInitialized) or (not FileExists(AFileName)) then Exit;
  P := StringReplace(AFileName, '\', '\\', [rfReplaceAll]);
  P := StringReplace(P, '"', '\"', [rfReplaceAll]);
  if FConnector.ExecString(
      'import hashlib' + LineEnding +
      '_hem_sha=hashlib.sha256()' + LineEnding +
      'with open(r"' + P + '","rb") as _hem_f:' + LineEnding +
      '    for _hem_chunk in iter(lambda:_hem_f.read(1048576), b""):' + LineEnding +
      '        _hem_sha.update(_hem_chunk)' + LineEnding +
      '_hem_sha256=_hem_sha.hexdigest()') then
    Result := LowerCase(Trim(FConnector.GetVar('_hem_sha256')));
end;

function TfrmMain.VerifyConfiguredModel: Boolean;
var
  Actual: string;
begin
  Result := False;
  if not FileExists(FEdModel.Text) then
  begin
    ShowMessage('Modelo não encontrado: ' + FEdModel.Text);
    Exit;
  end;
  if (FModelID > 0) and (FModelSHA256 <> '') then
  begin
    SetStatus('Verificando SHA-256 do modelo...');
    Application.ProcessMessages;
    Actual := ComputeFileSHA256(FEdModel.Text);
    if Actual = '' then
    begin
      ShowMessage('Não foi possível calcular SHA-256 do modelo.');
      Exit;
    end;
    if Actual <> FModelSHA256 then
    begin
      ShowMessage('O arquivo de modelo local não corresponde ao SHA-256 configurado no protocolo.' +
        LineEnding + 'Esperado: ' + FModelSHA256 + LineEnding + 'Obtido: ' + Actual);
      Exit;
    end;
  end;
  Result := True;
end;

function TfrmMain.FindSummary(const ACode: string): Integer;
var I: Integer;
begin
  for I := 0 to High(FSummaries) do
    if FSummaries[I].Code = ACode then Exit(I);
  Result := -1;
end;

procedure TfrmMain.AddSummary(const ACode: string; AConfidence: Double);
var I: Integer;
begin
  I := FindSummary(ACode);
  if I < 0 then
  begin
    SetLength(FSummaries, Length(FSummaries) + 1);
    I := High(FSummaries);
    FSummaries[I].Code := ACode;
    FSummaries[I].DisplayName := DisplayClass(ACode);
  end;
  Inc(FSummaries[I].Count);
  FSummaries[I].ConfidenceSum := FSummaries[I].ConfidenceSum + AConfidence;
end;

procedure TfrmMain.BuildSummaries;
var
  I: Integer;
  Code: string;
begin
  SetLength(FSummaries, 0);
  for I := 0 to High(FObjects) do
  begin
    Code := NormalizeClass(FObjects[I].ClassName);
    if IsClassEnabled(Code) and (FObjects[I].Confidence >= ThresholdForClass(Code)) then
      AddSummary(Code, FObjects[I].Confidence);
  end;
end;

procedure TfrmMain.UpdateGrid;
var
  I: Integer;
  Avg: Double;
begin
  FGrid.RowCount := Max(2, Length(FSummaries) + 1);
  for I := 1 to FGrid.RowCount - 1 do
  begin
    FGrid.Cells[0,I] := ''; FGrid.Cells[1,I] := ''; FGrid.Cells[2,I] := '';
  end;
  for I := 0 to High(FSummaries) do
  begin
    if FSummaries[I].Count > 0 then Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
    else Avg := 0;
    FGrid.Cells[0,I+1] := FSummaries[I].DisplayName;
    FGrid.Cells[1,I+1] := IntToStr(FSummaries[I].Count);
    FGrid.Cells[2,I+1] := FormatFloat('0.000', Avg);
  end;
end;

procedure TfrmMain.DrawDetections;
var
  Bmp: TBitmap;
  I, J: Integer;
  Code, LabelText: string;
  Tokens, XY: TStringList;
  Points: array of TPoint;
begin
  if FCurrentImage = '' then Exit;
  FImage.Picture.LoadFromFile(FCurrentImage);
  if FImage.Picture.Graphic = nil then Exit;

  Bmp := TBitmap.Create;
  Tokens := TStringList.Create;
  XY := TStringList.Create;
  try
    Bmp.SetSize(FImage.Picture.Graphic.Width, FImage.Picture.Graphic.Height);
    Bmp.Canvas.Draw(0, 0, FImage.Picture.Graphic);
    Bmp.Canvas.Brush.Style := bsClear;
    Bmp.Canvas.Pen.Width := 2;
    Bmp.Canvas.Font.Size := 9;

    for I := 0 to High(FObjects) do
    begin
      Code := NormalizeClass(FObjects[I].ClassName);
      if not IsClassEnabled(Code) then Continue;
      if FObjects[I].Confidence < ThresholdForClass(Code) then Continue;

      Bmp.Canvas.Pen.Color := ColorForClass(Code);
      Bmp.Canvas.Font.Color := ColorForClass(Code);

      Tokens.Clear;
      ExtractStrings(['|'], [], PChar(FObjects[I].Polygon), Tokens);
      if Tokens.Count >= 3 then
      begin
        SetLength(Points, Tokens.Count + 1);
        for J := 0 to Tokens.Count - 1 do
        begin
          XY.Clear;
          ExtractStrings([':'], [], PChar(Tokens[J]), XY);
          if XY.Count >= 2 then
          begin
            Points[J].X := StrToIntDef(XY[0], FObjects[I].X1);
            Points[J].Y := StrToIntDef(XY[1], FObjects[I].Y1);
          end;
        end;
        Points[High(Points)] := Points[0];
        Bmp.Canvas.Polyline(Points);
      end
      else
        Bmp.Canvas.Rectangle(FObjects[I].X1, FObjects[I].Y1,
          FObjects[I].X2, FObjects[I].Y2);

      LabelText := DisplayClass(Code) + ' ' +
        FormatFloat('0.0', FObjects[I].Confidence * 100) + '%';
      Bmp.Canvas.TextOut(FObjects[I].X1 + 2, FObjects[I].Y1 + 2, LabelText);
    end;
    FImage.Picture.Assign(Bmp);
  finally
    XY.Free; Tokens.Free; Bmp.Free;
  end;
end;

procedure TfrmMain.BuildDeterministicReport;
var
  S: TStringList;
  I: Integer;
  Avg: Double;
begin
  S := TStringList.Create;
  try
    S.Add('ANÁLISE DE LÂMINA - RESULTADO EXPERIMENTAL');
    S.Add('');
    if FSampleID > 0 then
      S.Add(Format('Paciente #%d | Amostra #%d | Protocolo: %s',
        [FPatientID, FSampleID, FProtocolCode]));
    S.Add('Imagem: ' + FCurrentImage);
    S.Add('Modelo: ' + FYolo.ModelPath);
    if FModelVersion <> '' then S.Add('Versão cadastrada: ' + FModelVersion);
    S.Add('Confiança global mínima: ' + FormatFloat('0.000', FYolo.ConfidenceThreshold));
    if FYolo.ImageSize > 0 then S.Add('imgsz: ' + IntToStr(FYolo.ImageSize));
    S.Add('Detecções brutas: ' + IntToStr(Length(FObjects)));
    S.Add('');
    S.Add('CONTAGEM POR COMPONENTE');
    for I := 0 to High(FSummaries) do
    begin
      if FSummaries[I].Count > 0 then Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
      else Avg := 0;
      S.Add(Format('%s: %d | confiança média: %.3f',
        [FSummaries[I].DisplayName, FSummaries[I].Count, Avg]));
    end;
    S.Add('');
    S.Add('Resultado de visão computacional para pesquisa/teste.');
    S.Add('Não representa validação laboratorial ou diagnóstico clínico.');
    FLastDeterministicReport := S.Text;
    FMemo.Lines.Text := FLastDeterministicReport;
  finally
    S.Free;
  end;
end;

procedure TfrmMain.AnalyzeClick(Sender: TObject);
begin
  if (FCurrentImage = '') or not FileExists(FCurrentImage) then
  begin
    ShowMessage('Carregue uma imagem de lâmina antes de analisar.'); Exit;
  end;
  if not FConnector.IsInitialized then
  begin
    ShowMessage('Python não está inicializado: ' + FConnector.LastError); Exit;
  end;
  if not VerifyConfiguredModel then Exit;

  FYolo.ModelPath := FEdModel.Text;
  FYolo.ConfidenceThreshold := ConfidenceValue;
  FYolo.ImageSize := ImageSizeValue;
  FYolo.Device := Trim(FEdDevice.Text);

  Screen.Cursor := crHourGlass;
  FBtnAnalyze.Enabled := False;
  SetStatus('Executando análise YOLO...');
  Application.ProcessMessages;
  try
    if not FYolo.DetectObjects(FCurrentImage, FObjects) then
    begin
      Log('Erro YOLO: ' + FYolo.LastError);
      ShowMessage('Falha na análise: ' + FYolo.LastError);
      SetStatus('Falha na análise.'); Exit;
    end;
    BuildSummaries;
    UpdateGrid;
    DrawDetections;
    BuildDeterministicReport;
    FBtnExport.Enabled := True;
    FBtnAIReport.Enabled := FChatConfigured;
    FBtnSend.Enabled := (FSampleID > 0) and (FApi <> nil);
    SetStatus(Format('Análise concluída: %d detecção(ões) brutas.', [Length(FObjects)]));
  finally
    FBtnAnalyze.Enabled := True;
    Screen.Cursor := crDefault;
  end;
end;

function TfrmMain.BuildCountPayload: TJSONObject;
var
  Components, Dets: TJSONArray;
  Comp, Det, Meta: TJSONObject;
  I, J, AcceptedTotal: Integer;
  Avg: Double;
  Code: string;
begin
  AcceptedTotal := 0;
  for I := 0 to High(FSummaries) do
    Inc(AcceptedTotal, FSummaries[I].Count);

  Result := TJSONObject.Create;
  Result.Add('sample_id', FSampleID);
  Result.Add('method', 'yolo-seg-lazarus');
  Result.Add('algorithm_version', '1.1-lazarus');
  Result.Add('source_client', 'LAZARUS');
  if FModelID > 0 then Result.Add('model_id', FModelID);
  if FModelSHA256 <> '' then Result.Add('model_sha256', FModelSHA256);
  Result.Add('model_path', FYolo.ModelPath);
  if FScaleLabel <> '' then Result.Add('scale_label', FScaleLabel);
  if FMagnification > 0 then Result.Add('magnification', FMagnification);
  Result.Add('image_quality', 'REVISAR');
  Result.Add('total_cells', AcceptedTotal);
  Result.Add('notes', 'Campo enviado pelo Hemácias Analyzer Lazarus.');

  Components := TJSONArray.Create;
  Result.Add('components', Components);
  for I := 0 to High(FSummaries) do
  begin
    if FSummaries[I].Count > 0 then Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
    else Avg := 0;

    Comp := TJSONObject.Create;
    Comp.Add('code', FSummaries[I].Code);
    Comp.Add('name', FSummaries[I].DisplayName);
    Comp.Add('quantity', FSummaries[I].Count);
    Comp.Add('confidence', Avg);

    Meta := TJSONObject.Create;
    Meta.Add('source', 'lazarus');
    Meta.Add('configured_threshold', ThresholdForClass(FSummaries[I].Code));
    Dets := TJSONArray.Create;
    Meta.Add('detections', Dets);

    for J := 0 to High(FObjects) do
    begin
      Code := NormalizeClass(FObjects[J].ClassName);
      if (Code = FSummaries[I].Code) and
         (FObjects[J].Confidence >= ThresholdForClass(Code)) then
      begin
        Det := TJSONObject.Create;
        Det.Add('confidence', FObjects[J].Confidence);
        Det.Add('x1', FObjects[J].X1);
        Det.Add('y1', FObjects[J].Y1);
        Det.Add('x2', FObjects[J].X2);
        Det.Add('y2', FObjects[J].Y2);
        if FObjects[J].Polygon <> '' then Det.Add('polygon', FObjects[J].Polygon);
        Dets.Add(Det);
      end;
    end;
    Comp.Add('metadata', Meta);
    Components.Add(Comp);
  end;
end;

procedure TfrmMain.SendClick(Sender: TObject);
var
  Payload: TJSONObject;
  CountID, ImageID, FieldID: Int64;
  FieldNo: Integer;
begin
  if (FApi = nil) or (FSampleID < 1) then
  begin
    ShowMessage('Vincule paciente e amostra antes de enviar.'); Exit;
  end;
  if Length(FSummaries) = 0 then
  begin
    ShowMessage('Execute a análise antes de enviar.'); Exit;
  end;
  if not VerifyConfiguredModel then Exit;

  Payload := BuildCountPayload;
  try
    SetStatus('Enviando campo e imagem ao servidor...');
    Screen.Cursor := crHourGlass;
    Application.ProcessMessages;
    if not FApi.CreateCount(Payload, FCurrentImage, CountID, ImageID, FieldID, FieldNo) then
    begin
      ShowMessage('Falha ao enviar: ' + FApi.LastError);
      SetStatus('Falha no envio.');
      Exit;
    end;

    Log(Format('Campo #%d enviado. count_id=%d, field_id=%d, image_id=%d.',
      [FieldNo, CountID, FieldID, ImageID]));
    SetStatus(Format('Campo #%d registrado no servidor.', [FieldNo]));
    FBtnSend.Enabled := False;
  finally
    Screen.Cursor := crDefault;
    Payload.Free;
  end;
end;

procedure TfrmMain.ExportJSON(const AFileName: string);
var
  Root, Item, Det: TJSONObject;
  Arr, Dets: TJSONArray;
  I: Integer;
  Avg: Double;
  S: TStringList;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('generated_at', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    Root.Add('image', FCurrentImage);
    Root.Add('patient_id', FPatientID);
    Root.Add('sample_id', FSampleID);
    Root.Add('protocol_code', FProtocolCode);
    Root.Add('model', FYolo.ModelPath);
    Root.Add('model_id', FModelID);
    Root.Add('model_version', FModelVersion);
    Root.Add('model_sha256', FModelSHA256);
    Root.Add('confidence_threshold', FYolo.ConfidenceThreshold);
    Root.Add('imgsz', FYolo.ImageSize);
    Root.Add('total_objects', Length(FObjects));

    Arr := TJSONArray.Create; Root.Add('components', Arr);
    for I := 0 to High(FSummaries) do
    begin
      if FSummaries[I].Count > 0 then Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
      else Avg := 0;
      Item := TJSONObject.Create;
      Item.Add('code', FSummaries[I].Code);
      Item.Add('name', FSummaries[I].DisplayName);
      Item.Add('quantity', FSummaries[I].Count);
      Item.Add('mean_confidence', Avg);
      Arr.Add(Item);
    end;

    Dets := TJSONArray.Create; Root.Add('detections', Dets);
    for I := 0 to High(FObjects) do
    begin
      Det := TJSONObject.Create;
      Det.Add('class', NormalizeClass(FObjects[I].ClassName));
      Det.Add('confidence', FObjects[I].Confidence);
      Det.Add('x1', FObjects[I].X1); Det.Add('y1', FObjects[I].Y1);
      Det.Add('x2', FObjects[I].X2); Det.Add('y2', FObjects[I].Y2);
      if FObjects[I].Polygon <> '' then Det.Add('polygon', FObjects[I].Polygon);
      Dets.Add(Det);
    end;

    S := TStringList.Create;
    try S.Text := Root.AsJSON; S.SaveToFile(AFileName); finally S.Free; end;
  finally
    Root.Free;
  end;
end;

procedure TfrmMain.ExportCSV(const AFileName: string);
var
  S: TStringList;
  I: Integer;
  Avg: Double;
begin
  S := TStringList.Create;
  try
    S.Add('component_code;component_name;quantity;mean_confidence');
    for I := 0 to High(FSummaries) do
    begin
      if FSummaries[I].Count > 0 then Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
      else Avg := 0;
      S.Add(FSummaries[I].Code + ';' + FSummaries[I].DisplayName + ';' +
        IntToStr(FSummaries[I].Count) + ';' +
        StringReplace(FormatFloat('0.000000', Avg), ',', '.', [rfReplaceAll]));
    end;
    S.SaveToFile(AFileName);
  finally S.Free; end;
end;

procedure TfrmMain.ExportText(const AFileName: string);
var S: TStringList;
begin
  S := TStringList.Create;
  try S.Text := FMemo.Lines.Text; S.SaveToFile(AFileName); finally S.Free; end;
end;

procedure TfrmMain.ExportClick(Sender: TObject);
var Ext: string;
begin
  if Length(FSummaries) = 0 then
  begin
    ShowMessage('Execute uma análise antes de emitir o resultado.'); Exit;
  end;
  FSaveReport.FileName := 'resultado_lamina_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.json';
  if not FSaveReport.Execute then Exit;
  Ext := LowerCase(ExtractFileExt(FSaveReport.FileName));
  if Ext = '.csv' then ExportCSV(FSaveReport.FileName)
  else if Ext = '.txt' then ExportText(FSaveReport.FileName)
  else ExportJSON(FSaveReport.FileName);
  SetStatus('Resultado salvo: ' + FSaveReport.FileName);
end;

procedure TfrmMain.AIReportClick(Sender: TObject);
var Prompt: string;
begin
  if FLastDeterministicReport = '' then Exit;
  Prompt :=
    'Você está auxiliando uma aplicação experimental de contagem microscópica. ' +
    'Use SOMENTE os números fornecidos abaixo. Não invente contagens, diagnóstico, ' +
    'faixa de referência ou interpretação clínica. Gere um resumo técnico curto, ' +
    'indicando quais componentes foram detectados, confiança e limitações. ' +
    'Deixe explícito que o resultado precisa de validação laboratorial.' +
    LineEnding + LineEnding + FLastDeterministicReport;

  SetStatus('Gerando parecer textual...');
  Screen.Cursor := crHourGlass;
  try
    if FChatGPT.SendQuestion(Prompt) then
    begin
      FMemo.Lines.Add(''); FMemo.Lines.Add('PARECER TEXTUAL DA IA');
      FMemo.Lines.Add(string(FChatGPT.Response));
      SetStatus('Parecer textual gerado.');
    end
    else
    begin
      ShowMessage('Não foi possível gerar o parecer. Verifique a configuração do TCHATGPT.');
      SetStatus('Falha no parecer de IA.');
    end;
  finally Screen.Cursor := crDefault; end;
end;

procedure TfrmMain.ClearClick(Sender: TObject);
begin
  SetLength(FObjects, 0);
  SetLength(FSummaries, 0);
  FCurrentImage := '';
  FEdImage.Clear;
  FImage.Picture.Clear;
  FMemo.Clear;
  FLastDeterministicReport := '';
  UpdateGrid;
  FBtnExport.Enabled := False;
  FBtnAIReport.Enabled := False;
  FBtnSend.Enabled := False;
  SetStatus('Pronto.');
end;

end.
