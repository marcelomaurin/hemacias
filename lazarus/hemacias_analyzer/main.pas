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
    FBtnNewField: TButton;
    FBtnSummary: TButton;
    FBtnExport: TButton;
    FBtnAIReport: TButton;
    FBtnModel: TButton;
    FBtnClear: TButton;
    FBtnReviewDelete: TButton;
    FBtnReviewClass: TButton;
    FBtnReviewAdd: TButton;
    FBtnReviewSave: TButton;
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
    FCbReviewClass: TComboBox;

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
    FQualityStatus: string;
    FQualityScore: Double;
    FFocusScore: Double;
    FQualityReason: string;
    FShowingSampleSummary: Boolean;
    FLastImageID: Int64;
    FSelectedObject: Integer;
    FAddReviewMode: Boolean;

    procedure BuildUI;
    procedure InitializeAI;
    procedure SetStatus(const AText: string);
    procedure Log(const AText: string);

    procedure LoadImageClick(Sender: TObject);
    procedure SelectModelClick(Sender: TObject);
    procedure AnalyzeClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure NewFieldClick(Sender: TObject);
    procedure SummaryClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure AIReportClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ReviewDeleteClick(Sender: TObject);
    procedure ReviewClassClick(Sender: TObject);
    procedure ReviewAddClick(Sender: TObject);
    procedure ReviewSaveClick(Sender: TObject);
    procedure ImageMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
    function EvaluateImageQuality: Boolean;

    procedure BuildSummaries;
    procedure UpdateGrid;
    procedure DrawDetections;
    procedure BuildDeterministicReport;
    procedure ShowSampleSummary;
    procedure PopulateProtocols(AConfig: TJSONObject);
    procedure ApplySampleConfig(AConfig: TJSONObject);
    procedure LoadProtocolItems(AProtocol: TJSONObject);
    procedure PopulateReviewClasses;
    procedure RefreshAfterReview;
    function ScreenToImage(const X, Y: Integer; out IX, IY: Integer): Boolean;
    function FindObjectAt(const IX, IY: Integer): Integer;
    procedure DeleteObject(AIndex: Integer);
    procedure AddManualObject(const IX, IY: Integer);

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

function ObjBool(AObj: TJSONObject; const AName: string; ADefault: Boolean = False): Boolean;
var
  D: TJSONData;
  S: string;
begin
  Result := ADefault;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D = nil) or (D.JSONType = jtNull) then Exit;
  if D.JSONType = jtBoolean then Exit(D.AsBoolean);
  S := LowerCase(Trim(D.AsString));
  Result := (S='1') or (S='true') or (S='yes') or (S='sim');
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'Analisador de Lâminas - Lazarus AI Suite';
  FConfigJSON := nil;
  FApi := nil;
  FPatientID := 0;
  FSampleID := 0;
  FQualityStatus := 'REVISAR';
  FQualityScore := 0;
  FFocusScore := 0;
  FQualityReason := '';
  FShowingSampleSummary := False;
  FLastImageID := 0;
  FSelectedObject := -1;
  FAddReviewMode := False;
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
  FBtnSend.SetBounds(245, 10, 105, 32);
  FBtnSend.Caption := 'Enviar campo';
  FBtnSend.OnClick := @SendClick;
  FBtnSend.Enabled := False;

  FBtnNewField := TButton.Create(Self);
  FBtnNewField.Parent := FTop;
  FBtnNewField.SetBounds(360, 10, 95, 32);
  FBtnNewField.Caption := 'Novo campo';
  FBtnNewField.OnClick := @NewFieldClick;
  FBtnNewField.Enabled := False;

  FBtnSummary := TButton.Create(Self);
  FBtnSummary.Parent := FTop;
  FBtnSummary.SetBounds(465, 10, 105, 32);
  FBtnSummary.Caption := 'Relatório amostra';
  FBtnSummary.OnClick := @SummaryClick;
  FBtnSummary.Enabled := False;

  FBtnExport := TButton.Create(Self);
  FBtnExport.Parent := FTop;
  FBtnExport.SetBounds(580, 10, 115, 32);
  FBtnExport.Caption := 'Emitir resultado';
  FBtnExport.OnClick := @ExportClick;
  FBtnExport.Enabled := False;

  FBtnAIReport := TButton.Create(Self);
  FBtnAIReport.Parent := FTop;
  FBtnAIReport.SetBounds(705, 10, 125, 32);
  FBtnAIReport.Caption := 'Parecer com IA';
  FBtnAIReport.OnClick := @AIReportClick;
  FBtnAIReport.Enabled := False;

  FBtnClear := TButton.Create(Self);
  FBtnClear.Parent := FTop;
  FBtnClear.SetBounds(840, 10, 80, 32);
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
  L.SetBounds(10, 302, 170, 20); L.Caption := 'Revisão humana';
  L.Font.Style := [fsBold];

  FCbReviewClass := TComboBox.Create(Self);
  FCbReviewClass.Parent := FRight;
  FCbReviewClass.SetBounds(8, 324, 150, 27);
  FCbReviewClass.Style := csDropDownList;

  FBtnReviewClass := TButton.Create(Self);
  FBtnReviewClass.Parent := FRight;
  FBtnReviewClass.SetBounds(164, 323, 98, 29);
  FBtnReviewClass.Caption := 'Trocar classe';
  FBtnReviewClass.OnClick := @ReviewClassClick;

  FBtnReviewDelete := TButton.Create(Self);
  FBtnReviewDelete.Parent := FRight;
  FBtnReviewDelete.SetBounds(268, 323, 106, 29);
  FBtnReviewDelete.Caption := 'Excluir';
  FBtnReviewDelete.OnClick := @ReviewDeleteClick;

  FBtnReviewAdd := TButton.Create(Self);
  FBtnReviewAdd.Parent := FRight;
  FBtnReviewAdd.SetBounds(8, 357, 150, 29);
  FBtnReviewAdd.Caption := 'Adicionar no clique';
  FBtnReviewAdd.OnClick := @ReviewAddClick;

  FBtnReviewSave := TButton.Create(Self);
  FBtnReviewSave.Parent := FRight;
  FBtnReviewSave.SetBounds(164, 357, 210, 29);
  FBtnReviewSave.Caption := 'Salvar revisão no dataset';
  FBtnReviewSave.OnClick := @ReviewSaveClick;
  FBtnReviewSave.Enabled := False;

  L := TLabel.Create(Self); L.Parent := FRight;
  L.SetBounds(10, 397, 300, 20); L.Caption := 'Relatório / observações';

  FMemo := TMemo.Create(Self); FMemo.Parent := FRight;
  FMemo.SetBounds(8, 420, 368, 210);
  FMemo.ScrollBars := ssAutoVertical; FMemo.WordWrap := True;

  FBottom := TPanel.Create(Self); FBottom.Parent := Self;
  FBottom.Align := alBottom; FBottom.Height := 28; FBottom.BevelOuter := bvNone;
  FStatus := TStatusBar.Create(Self); FStatus.Parent := FBottom;
  FStatus.Align := alClient; FStatus.SimplePanel := True;

  FImage := TImage.Create(Self); FImage.Parent := Self;
  FImage.Align := alClient; FImage.Center := True;
  FImage.Proportional := True; FImage.Stretch := True;
  FImage.OnMouseDown := @ImageMouseDown;

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

  FBtnSummary.Enabled := True;
  FBtnNewField.Enabled := True;
  Log(Format('Paciente #%d / amostra #%d vinculados ao protocolo %s.',
    [FPatientID, FSampleID, FProtocolCode]));
  ShowSampleSummary;
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

  PopulateReviewClasses;
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
  FShowingSampleSummary := False;
  FCurrentImage := FOpenImage.FileName;
  FEdImage.Text := FCurrentImage;
  FImage.Picture.LoadFromFile(FCurrentImage);
  SetLength(FObjects, 0);
  SetLength(FSummaries, 0);
  FQualityStatus := 'REVISAR';
  FQualityScore := 0;
  FFocusScore := 0;
  FQualityReason := '';
  FSelectedObject := -1;
  FAddReviewMode := False;
  FLastImageID := 0;
  FBtnReviewSave.Enabled := False;
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

function TfrmMain.EvaluateImageQuality: Boolean;
var
  P, S, ReasonsText: string;
  FS: TFormatSettings;
begin
  Result := False;
  if (FCurrentImage = '') or (not FileExists(FCurrentImage)) then Exit;

  P := StringReplace(FCurrentImage, '\', '\\', [rfReplaceAll]);
  P := StringReplace(P, '"', '\"', [rfReplaceAll]);

  S :=
    'import cv2, numpy as np' + LineEnding +
    '_q_img=cv2.imread(r"' + P + '")' + LineEnding +
    'if _q_img is None: raise RuntimeError("imagem não pôde ser carregada")' + LineEnding +
    '_q_gray=cv2.cvtColor(_q_img,cv2.COLOR_BGR2GRAY)' + LineEnding +
    '_q_focus=float(cv2.Laplacian(_q_gray,cv2.CV_64F).var())' + LineEnding +
    '_q_mean=float(np.mean(_q_gray))' + LineEnding +
    '_q_shadow=float(np.mean(_q_gray<=8))' + LineEnding +
    '_q_high=float(np.mean(_q_gray>=247))' + LineEnding +
    '_q_h,_q_w=_q_gray.shape[:2]' + LineEnding +
    '_q_ys=np.linspace(0,_q_h,4,dtype=int); _q_xs=np.linspace(0,_q_w,4,dtype=int)' + LineEnding +
    '_q_tiles=[float(np.mean(_q_gray[_q_ys[y]:_q_ys[y+1],_q_xs[x]:_q_xs[x+1]])) for y in range(3) for x in range(3)]' + LineEnding +
    '_q_cv=float(np.std(_q_tiles)/max(np.mean(_q_tiles),1.0))' + LineEnding +
    '_q_reasons=[]; _q_pen=0.0; _q_hard=False' + LineEnding +
    'if _q_focus<35: _q_reasons.append("foco abaixo do mínimo"); _q_pen+=55; _q_hard=True' + LineEnding +
    'if _q_mean<35: _q_reasons.append("imagem muito escura"); _q_pen+=30' + LineEnding +
    'elif _q_mean>225: _q_reasons.append("imagem muito clara"); _q_pen+=30' + LineEnding +
    'if _q_shadow>0.12: _q_reasons.append("excesso de pixels escuros/saturados"); _q_pen+=min(25,_q_shadow*100)' + LineEnding +
    'if _q_high>0.12: _q_reasons.append("excesso de pixels claros/saturados"); _q_pen+=min(25,_q_high*100)' + LineEnding +
    'if _q_cv>0.28: _q_reasons.append("iluminação muito desigual"); _q_pen+=min(30,_q_cv*60)' + LineEnding +
    '_q_score=max(0.0,100.0-_q_pen)' + LineEnding +
    '_q_status="REJEITADA" if (_q_hard or _q_score<45) else ("REVISAR" if (_q_score<75 or _q_reasons) else "ACEITA")' + LineEnding +
    '_q_reason="; ".join(_q_reasons)' + LineEnding +
    '_q_ok=True';

  if not FConnector.ExecString(S) then
  begin
    Log('Falha ao avaliar qualidade: ' + FConnector.LastError);
    Exit;
  end;
  if FConnector.GetVar('_q_ok') <> 'True' then Exit;

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FQualityStatus := Trim(FConnector.GetVar('_q_status'));
  FQualityScore := StrToFloatDef(StringReplace(FConnector.GetVar('_q_score'), ',', '.', [rfReplaceAll]), 0, FS);
  FFocusScore := StrToFloatDef(StringReplace(FConnector.GetVar('_q_focus'), ',', '.', [rfReplaceAll]), 0, FS);
  ReasonsText := Trim(FConnector.GetVar('_q_reason'));
  FQualityReason := ReasonsText;
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

      if I = FSelectedObject then
      begin
        Bmp.Canvas.Pen.Color := clYellow;
        Bmp.Canvas.Pen.Width := 4;
      end
      else
      begin
        Bmp.Canvas.Pen.Color := ColorForClass(Code);
        Bmp.Canvas.Pen.Width := 2;
      end;
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
    S.Add('Qualidade: ' + FQualityStatus + ' | score: ' + FormatFloat('0.0', FQualityScore) +
      ' | foco: ' + FormatFloat('0.0', FFocusScore));
    if FQualityReason <> '' then S.Add('Qualidade - observações: ' + FQualityReason);
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

  SetStatus('Avaliando qualidade da imagem...');
  Application.ProcessMessages;
  if not EvaluateImageQuality then
  begin
    ShowMessage('Não foi possível avaliar a qualidade da imagem.');
    Exit;
  end;
  if FQualityReason <> '' then
    Log(Format('Qualidade: %s | score %.1f | foco %.1f | %s',
      [FQualityStatus, FQualityScore, FFocusScore, FQualityReason]))
  else
    Log(Format('Qualidade: %s | score %.1f | foco %.1f',
      [FQualityStatus, FQualityScore, FFocusScore]));
  if FQualityStatus = 'REJEITADA' then
  begin
    ShowMessage('Campo rejeitado pelo controle de qualidade.' + LineEnding +
      'Score: ' + FormatFloat('0.0', FQualityScore) + LineEnding +
      FQualityReason);
    BuildDeterministicReport;
    FBtnExport.Enabled := True;
    FBtnSend.Enabled := (FSampleID > 0) and (FApi <> nil);
    Exit;
  end;

  FYolo.ModelPath := FEdModel.Text;
  FYolo.ConfidenceThreshold := ConfidenceValue;
  FYolo.ImageSize := ImageSizeValue;
  FYolo.Device := Trim(FEdDevice.Text);

  FShowingSampleSummary := False;
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
    FSelectedObject := -1;
    FAddReviewMode := False;
    SetStatus(Format('Análise concluída: %d detecção(ões) brutas. Clique em uma célula para revisar.', [Length(FObjects)]));
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
  Result.Add('image_quality', FQualityStatus);
  Result.Add('quality_score', FQualityScore);
  Result.Add('focus_score', FFocusScore);
  if FQualityReason <> '' then Result.Add('quality_reason', FQualityReason);
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
  if (Length(FSummaries) = 0) and (FQualityStatus <> 'REJEITADA') then
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

    FLastImageID := ImageID;
    FBtnReviewSave.Enabled := FLastImageID > 0;
    if FLastImageID > 0 then
      Log('A revisão humana desta imagem já pode ser salva no dataset.');
    Log(Format('Campo #%d enviado. count_id=%d, field_id=%d, image_id=%d.',
      [FieldNo, CountID, FieldID, ImageID]));
    SetStatus(Format('Campo #%d registrado no servidor.', [FieldNo]));
    FBtnSend.Enabled := False;
    FBtnNewField.Enabled := True;
    FBtnSummary.Enabled := True;
    ShowSampleSummary;
  finally
    Screen.Cursor := crDefault;
    Payload.Free;
  end;
end;

procedure TfrmMain.NewFieldClick(Sender: TObject);
begin
  SetLength(FObjects, 0);
  SetLength(FSummaries, 0);
  FCurrentImage := '';
  FEdImage.Clear;
  FImage.Picture.Clear;
  FLastDeterministicReport := '';
  FQualityStatus := 'REVISAR';
  FQualityScore := 0;
  FFocusScore := 0;
  FQualityReason := '';
  FLastImageID := 0;
  FSelectedObject := -1;
  FAddReviewMode := False;
  FBtnReviewSave.Enabled := False;
  UpdateGrid;
  FBtnSend.Enabled := False;
  FBtnExport.Enabled := False;
  FBtnAIReport.Enabled := False;
  FMemo.Clear;
  if FSampleID > 0 then
    ShowSampleSummary;
  SetStatus('Novo campo: carregue a próxima imagem microscópica.');
end;

procedure TfrmMain.SummaryClick(Sender: TObject);
begin
  ShowSampleSummary;
end;

procedure TfrmMain.ShowSampleSummary;
var
  Obj: TJSONObject;
  D: TJSONData;
  Totals: TJSONObject;
  Arr: TJSONArray;
  Row: TJSONObject;
  I: Integer;
  S: TStringList;
  Ready: Boolean;
begin
  if (FApi = nil) or (FSampleID < 1) then Exit;
  Obj := FApi.GetSampleSummary(FSampleID);
  if Obj = nil then
  begin
    Log('Falha ao consultar consolidado: ' + FApi.LastError);
    Exit;
  end;

  S := TStringList.Create;
  try
    S.Add('CONSOLIDADO DA AMOSTRA');
    S.Add('');
    S.Add('Paciente: ' + FEdPatientName.Text);
    S.Add('Amostra: ' + FEdSampleCode.Text);
    S.Add('Protocolo: ' + FProtocolCode);

    D := Obj.Find('totals');
    if D is TJSONObject then
    begin
      Totals := TJSONObject(D);
      Ready := ObjBool(Totals, 'ready', False);
      S.Add(Format('Campos: %d | válidos: %d | rejeitados/excluídos: %d | revisar: %d',
        [ObjInt(Totals,'fields',0), ObjInt(Totals,'accepted',0),
         ObjInt(Totals,'rejected',0), ObjInt(Totals,'review',0)]));
      S.Add(Format('Meta do protocolo: %d campos totais / %d válidos.',
        [ObjInt(Totals,'min_fields',0), ObjInt(Totals,'min_valid_fields',0)]));
      if Ready then S.Add('Status: PRONTO PARA CONSOLIDAÇÃO.')
      else S.Add('Status: ainda não atingiu os critérios mínimos do protocolo.');
    end;

    S.Add('');
    S.Add('RESULTADOS CONSOLIDADOS');
    D := Obj.Find('summary');
    if D is TJSONArray then
    begin
      Arr := TJSONArray(D);
      if Arr.Count = 0 then
        S.Add('Ainda não há campos ACEITOS e incluídos na consolidação.')
      else
      for I := 0 to Arr.Count - 1 do
      begin
        Row := TJSONObject(Arr.Items[I]);
        S.Add(Format('%s | campos=%d | média=%.2f | mediana=%.2f | mín=%.2f | máx=%.2f | DP=%.2f',
          [ObjStr(Row,'name',ObjStr(Row,'code','')),
           ObjInt(Row,'fields',0), ObjFloat(Row,'mean',0), ObjFloat(Row,'median',0),
           ObjFloat(Row,'min',0), ObjFloat(Row,'max',0), ObjFloat(Row,'stddev',0)]));
      end;
    end;

    S.Add('');
    S.Add('CAMPOS');
    D := Obj.Find('fields');
    if D is TJSONArray then
    begin
      Arr := TJSONArray(D);
      for I := 0 to Arr.Count - 1 do
      begin
        Row := TJSONObject(Arr.Items[I]);
        if ObjInt(Row,'included_in_summary',0)<>0 then
          S.Add(Format('#%d | %s | qualidade=%.1f | foco=%.1f | incluído=sim',
            [ObjInt(Row,'field_no',0), ObjStr(Row,'status',''),
             ObjFloat(Row,'quality_score',0), ObjFloat(Row,'focus_score',0)]))
        else
          S.Add(Format('#%d | %s | qualidade=%.1f | foco=%.1f | incluído=não',
            [ObjInt(Row,'field_no',0), ObjStr(Row,'status',''),
             ObjFloat(Row,'quality_score',0), ObjFloat(Row,'focus_score',0)]));
      end;
    end;

    S.Add('');
    S.Add('Relatório experimental. Requer validação laboratorial.');
    FMemo.Lines.Assign(S);
    FLastDeterministicReport := S.Text;
    FShowingSampleSummary := True;
    FBtnExport.Enabled := True;
    FBtnAIReport.Enabled := FChatConfigured;
  finally
    S.Free;
    Obj.Free;
  end;
end;


procedure TfrmMain.PopulateReviewClasses;
var
  I: Integer;
begin
  if FCbReviewClass = nil then Exit;
  FCbReviewClass.Items.Clear;
  for I := 0 to High(FProtocolItems) do
    if FProtocolItems[I].AIEnabled then
      FCbReviewClass.Items.AddObject(FProtocolItems[I].Name, TObject(PtrInt(I)));
  if FCbReviewClass.Items.Count = 0 then
  begin
    FCbReviewClass.Items.Add('Hemácia');
    FCbReviewClass.Items.Add('Leucócito');
    FCbReviewClass.Items.Add('Plaqueta');
    FCbReviewClass.Items.Add('Artefato');
  end;
  if FCbReviewClass.Items.Count > 0 then FCbReviewClass.ItemIndex := 0;
end;

function TfrmMain.ScreenToImage(const X, Y: Integer; out IX, IY: Integer): Boolean;
var
  IW, IH, DW, DH, OX, OY: Integer;
  Scale: Double;
begin
  Result := False;
  IX := 0; IY := 0;
  if (FImage.Picture.Graphic = nil) then Exit;
  IW := FImage.Picture.Graphic.Width;
  IH := FImage.Picture.Graphic.Height;
  if (IW <= 0) or (IH <= 0) or (FImage.ClientWidth <= 0) or (FImage.ClientHeight <= 0) then Exit;

  Scale := Min(FImage.ClientWidth / IW, FImage.ClientHeight / IH);
  DW := Round(IW * Scale);
  DH := Round(IH * Scale);
  OX := (FImage.ClientWidth - DW) div 2;
  OY := (FImage.ClientHeight - DH) div 2;
  if (X < OX) or (Y < OY) or (X >= OX + DW) or (Y >= OY + DH) then Exit;

  IX := EnsureRange(Round((X - OX) / Scale), 0, IW - 1);
  IY := EnsureRange(Round((Y - OY) / Scale), 0, IH - 1);
  Result := True;
end;

function TfrmMain.FindObjectAt(const IX, IY: Integer): Integer;
var
  I, BestArea, Area: Integer;
begin
  Result := -1;
  BestArea := MaxInt;
  for I := 0 to High(FObjects) do
    if (IX >= FObjects[I].X1) and (IX <= FObjects[I].X2) and
       (IY >= FObjects[I].Y1) and (IY <= FObjects[I].Y2) then
    begin
      Area := Max(1, FObjects[I].X2 - FObjects[I].X1) *
              Max(1, FObjects[I].Y2 - FObjects[I].Y1);
      if Area < BestArea then
      begin
        BestArea := Area;
        Result := I;
      end;
    end;
end;

procedure TfrmMain.DeleteObject(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FObjects)) then Exit;
  for I := AIndex to High(FObjects)-1 do
    FObjects[I] := FObjects[I+1];
  SetLength(FObjects, Length(FObjects)-1);
  FSelectedObject := -1;
  RefreshAfterReview;
end;

procedure TfrmMain.AddManualObject(const IX, IY: Integer);
var
  O: TYoloObject;
  R, Idx: Integer;
  Code: string;
begin
  if FCbReviewClass.ItemIndex < 0 then Exit;
  if Length(FProtocolItems) > 0 then
  begin
    Idx := PtrInt(FCbReviewClass.Items.Objects[FCbReviewClass.ItemIndex]);
    if (Idx >= 0) and (Idx <= High(FProtocolItems)) then
      Code := FProtocolItems[Idx].Code
    else
      Code := LowerCase(FCbReviewClass.Text);
  end
  else
  begin
    case FCbReviewClass.ItemIndex of
      0: Code := 'hemacia';
      1: Code := 'leucocito';
      2: Code := 'plaqueta';
      3: Code := 'artefato';
    else
      Code := LowerCase(FCbReviewClass.Text);
    end;
  end;

  R := 10;
  O.ClassName := Code;
  O.Confidence := 1.0;
  O.X1 := Max(0, IX-R);
  O.Y1 := Max(0, IY-R);
  O.X2 := Min(FImage.Picture.Graphic.Width-1, IX+R);
  O.Y2 := Min(FImage.Picture.Graphic.Height-1, IY+R);
  O.Polygon := Format('%d:%d|%d:%d|%d:%d|%d:%d',
    [O.X1,O.Y1,O.X2,O.Y1,O.X2,O.Y2,O.X1,O.Y2]);

  SetLength(FObjects, Length(FObjects)+1);
  FObjects[High(FObjects)] := O;
  FSelectedObject := High(FObjects);
  FAddReviewMode := False;
  FBtnReviewAdd.Caption := 'Adicionar no clique';
  RefreshAfterReview;
  SetStatus('Objeto manual adicionado. Revise e salve no dataset.');
end;

procedure TfrmMain.RefreshAfterReview;
begin
  BuildSummaries;
  UpdateGrid;
  DrawDetections;
  BuildDeterministicReport;
end;

procedure TfrmMain.ImageMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  IX, IY: Integer;
begin
  if Button <> mbLeft then Exit;
  if not ScreenToImage(X, Y, IX, IY) then Exit;

  if FAddReviewMode then
  begin
    AddManualObject(IX, IY);
    Exit;
  end;

  FSelectedObject := FindObjectAt(IX, IY);
  if FSelectedObject >= 0 then
  begin
    SetStatus(Format('Selecionado #%d: %s (%.1f%%).',
      [FSelectedObject+1, DisplayClass(NormalizeClass(FObjects[FSelectedObject].ClassName)),
       FObjects[FSelectedObject].Confidence*100]));
    DrawDetections;
  end
  else
    SetStatus('Nenhum objeto selecionado nesse ponto.');
end;

procedure TfrmMain.ReviewDeleteClick(Sender: TObject);
begin
  if FSelectedObject < 0 then
  begin
    ShowMessage('Clique primeiro sobre uma detecção para selecioná-la.');
    Exit;
  end;
  DeleteObject(FSelectedObject);
  SetStatus('Detecção removida da revisão.');
end;

procedure TfrmMain.ReviewClassClick(Sender: TObject);
var
  Idx: Integer;
  Code: string;
begin
  if FSelectedObject < 0 then
  begin
    ShowMessage('Clique primeiro sobre uma detecção para selecioná-la.');
    Exit;
  end;
  if FCbReviewClass.ItemIndex < 0 then Exit;

  if Length(FProtocolItems) > 0 then
  begin
    Idx := PtrInt(FCbReviewClass.Items.Objects[FCbReviewClass.ItemIndex]);
    if (Idx >= 0) and (Idx <= High(FProtocolItems)) then
      Code := FProtocolItems[Idx].Code
    else Exit;
  end
  else
  begin
    case FCbReviewClass.ItemIndex of
      0: Code := 'hemacia';
      1: Code := 'leucocito';
      2: Code := 'plaqueta';
      3: Code := 'artefato';
    else Exit;
    end;
  end;

  FObjects[FSelectedObject].ClassName := Code;
  FObjects[FSelectedObject].Confidence := 1.0;
  RefreshAfterReview;
  SetStatus('Classe corrigida manualmente para ' + DisplayClass(Code) + '.');
end;

procedure TfrmMain.ReviewAddClick(Sender: TObject);
begin
  if FCurrentImage = '' then
  begin
    ShowMessage('Carregue uma imagem antes de adicionar objetos.');
    Exit;
  end;
  FAddReviewMode := not FAddReviewMode;
  if FAddReviewMode then
  begin
    FBtnReviewAdd.Caption := 'Cancelar adição';
    SetStatus('Modo adicionar ativo: clique no centro da célula ausente.');
  end
  else
  begin
    FBtnReviewAdd.Caption := 'Adicionar no clique';
    SetStatus('Modo adicionar cancelado.');
  end;
end;

procedure TfrmMain.ReviewSaveClick(Sender: TObject);
var
  Arr: TJSONArray;
  Ann: TJSONObject;
  Poly: TJSONArray;
  P: TJSONArray;
  Tokens, XY: TStringList;
  I, J: Integer;
  Code: string;
begin
  if (FApi = nil) or (FLastImageID < 1) then
  begin
    ShowMessage('Envie o campo ao servidor antes de salvar a revisão.');
    Exit;
  end;

  Arr := TJSONArray.Create;
  Tokens := TStringList.Create;
  XY := TStringList.Create;
  try
    for I := 0 to High(FObjects) do
    begin
      Code := NormalizeClass(FObjects[I].ClassName);
      if not IsClassEnabled(Code) then Continue;

      Ann := TJSONObject.Create;
      Ann.Add('class_code', Code);
      Ann.Add('notes', 'Revisão humana realizada no Hemácias Analyzer Lazarus');
      Poly := TJSONArray.Create;
      Ann.Add('polygon', Poly);

      Tokens.Clear;
      ExtractStrings(['|'], [], PChar(FObjects[I].Polygon), Tokens);
      if Tokens.Count >= 3 then
      begin
        for J := 0 to Tokens.Count-1 do
        begin
          XY.Clear;
          ExtractStrings([':'], [], PChar(Tokens[J]), XY);
          if XY.Count >= 2 then
          begin
            P := TJSONArray.Create;
            P.Add(StrToIntDef(XY[0], FObjects[I].X1));
            P.Add(StrToIntDef(XY[1], FObjects[I].Y1));
            Poly.Add(P);
          end;
        end;
      end;

      if Poly.Count < 3 then
      begin
        Poly.Clear;
        P := TJSONArray.Create; P.Add(FObjects[I].X1); P.Add(FObjects[I].Y1); Poly.Add(P);
        P := TJSONArray.Create; P.Add(FObjects[I].X2); P.Add(FObjects[I].Y1); Poly.Add(P);
        P := TJSONArray.Create; P.Add(FObjects[I].X2); P.Add(FObjects[I].Y2); Poly.Add(P);
        P := TJSONArray.Create; P.Add(FObjects[I].X1); P.Add(FObjects[I].Y2); Poly.Add(P);
      end;
      Arr.Add(Ann);
    end;

    SetStatus('Salvando revisão humana no dataset...');
    Application.ProcessMessages;
    if not FApi.SaveAnnotations(FLastImageID, Arr) then
    begin
      ShowMessage('Falha ao salvar revisão: ' + FApi.LastError);
      SetStatus('Falha ao salvar revisão.');
      Exit;
    end;

    SetStatus(Format('Revisão salva: %d anotação(ões). Imagem marcada como REVISADA.',
      [Arr.Count]));
    Log(Format('Ground truth salvo no dataset para image_id=%d: %d objetos.',
      [FLastImageID, Arr.Count]));
  finally
    XY.Free;
    Tokens.Free;
    Arr.Free;
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
  if (not FShowingSampleSummary) and (Length(FSummaries) = 0) then
  begin
    ShowMessage('Execute uma análise antes de emitir o resultado.'); Exit;
  end;
  if FShowingSampleSummary then
  begin
    FSaveReport.FileName := 'relatorio_amostra_' +
      FormatDateTime('yyyymmdd_hhnnss', Now) + '.txt';
    FSaveReport.FilterIndex := 3;
  end
  else
  begin
    FSaveReport.FileName := 'resultado_lamina_' +
      FormatDateTime('yyyymmdd_hhnnss', Now) + '.json';
    FSaveReport.FilterIndex := 1;
  end;
  if not FSaveReport.Execute then Exit;
  Ext := LowerCase(ExtractFileExt(FSaveReport.FileName));
  if FShowingSampleSummary then
    ExportText(FSaveReport.FileName)
  else if Ext = '.csv' then ExportCSV(FSaveReport.FileName)
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
  FShowingSampleSummary := False;
  FLastImageID := 0;
  FSelectedObject := -1;
  FAddReviewMode := False;
  FBtnReviewSave.Enabled := False;
  UpdateGrid;
  FBtnExport.Enabled := False;
  FBtnAIReport.Enabled := False;
  FBtnSend.Enabled := False;
  FBtnSummary.Enabled := FSampleID > 0;
  FBtnNewField.Enabled := FSampleID > 0;
  SetStatus('Pronto.');
end;

end.
