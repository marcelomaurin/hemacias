unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, ComCtrls, fpjson, jsonparser, pythonconnector, yolodetect, chatgpt;

type
  TClassSummary = record
    Code: string;
    DisplayName: string;
    Count: Integer;
    ConfidenceSum: Double;
  end;
  TClassSummaryArray = array of TClassSummary;

  { TfrmMain }

  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FConnector: TPythonConnector;
    FYolo: TYOLO;
    FChatGPT: TCHATGPT;

    FTop: TPanel;
    FConfig: TPanel;
    FRight: TPanel;
    FBottom: TPanel;
    FImage: TImage;
    FGrid: TStringGrid;
    FMemo: TMemo;
    FStatus: TStatusBar;

    FBtnLoad: TButton;
    FBtnAnalyze: TButton;
    FBtnExport: TButton;
    FBtnAIReport: TButton;
    FBtnModel: TButton;
    FBtnClear: TButton;

    FEdImage: TEdit;
    FEdModel: TEdit;
    FEdConfidence: TEdit;
    FEdImageSize: TEdit;
    FEdDevice: TEdit;

    FOpenImage: TOpenDialog;
    FOpenModel: TOpenDialog;
    FSaveReport: TSaveDialog;

    FObjects: TYoloObjectArray;
    FSummaries: TClassSummaryArray;
    FCurrentImage: string;
    FLastDeterministicReport: string;

    procedure BuildUI;
    procedure InitializeAI;
    procedure SetStatus(const AText: string);
    procedure Log(const AText: string);

    procedure LoadImageClick(Sender: TObject);
    procedure SelectModelClick(Sender: TObject);
    procedure AnalyzeClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure AIReportClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);

    function ConfidenceValue: Double;
    function ImageSizeValue: Integer;
    function NormalizeClass(const AName: string): string;
    function DisplayClass(const ACode: string): string;
    function ColorForClass(const ACode: string): TColor;

    procedure BuildSummaries;
    procedure UpdateGrid;
    procedure DrawDetections;
    procedure BuildDeterministicReport;

    function FindSummary(const ACode: string): Integer;
    procedure AddSummary(const ACode: string; AConfidence: Double);

    procedure ExportJSON(const AFileName: string);
    procedure ExportCSV(const AFileName: string);
    procedure ExportText(const AFileName: string);
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

function JsonFloat(AValue: Double): TJSONFloatNumber;
begin
  Result := TJSONFloatNumber.Create(AValue);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'Analisador de Lâminas - Lazarus AI Suite';
  BuildUI;
  InitializeAI;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
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
  FBtnAnalyze.SetBounds(140, 10, 110, 32);
  FBtnAnalyze.Caption := 'Analisar';
  FBtnAnalyze.OnClick := @AnalyzeClick;

  FBtnExport := TButton.Create(Self);
  FBtnExport.Parent := FTop;
  FBtnExport.SetBounds(260, 10, 120, 32);
  FBtnExport.Caption := 'Emitir resultado';
  FBtnExport.OnClick := @ExportClick;
  FBtnExport.Enabled := False;

  FBtnAIReport := TButton.Create(Self);
  FBtnAIReport.Parent := FTop;
  FBtnAIReport.SetBounds(390, 10, 130, 32);
  FBtnAIReport.Caption := 'Parecer com IA';
  FBtnAIReport.OnClick := @AIReportClick;
  FBtnAIReport.Enabled := False;

  FBtnClear := TButton.Create(Self);
  FBtnClear.Parent := FTop;
  FBtnClear.SetBounds(530, 10, 90, 32);
  FBtnClear.Caption := 'Limpar';
  FBtnClear.OnClick := @ClearClick;

  FConfig := TPanel.Create(Self);
  FConfig.Parent := Self;
  FConfig.Align := alTop;
  FConfig.Height := 88;
  FConfig.BevelOuter := bvLowered;

  L := TLabel.Create(Self);
  L.Parent := FConfig;
  L.SetBounds(10, 8, 70, 20);
  L.Caption := 'Imagem:';
  FEdImage := TEdit.Create(Self);
  FEdImage.Parent := FConfig;
  FEdImage.SetBounds(78, 5, 510, 27);
  FEdImage.ReadOnly := True;

  L := TLabel.Create(Self);
  L.Parent := FConfig;
  L.SetBounds(10, 45, 60, 20);
  L.Caption := 'Modelo:';
  FEdModel := TEdit.Create(Self);
  FEdModel.Parent := FConfig;
  FEdModel.SetBounds(78, 42, 420, 27);
  FEdModel.Text := 'models' + PathDelim + 'blood-seg-v1.pt';

  FBtnModel := TButton.Create(Self);
  FBtnModel.Parent := FConfig;
  FBtnModel.SetBounds(505, 40, 83, 30);
  FBtnModel.Caption := 'Selecionar';
  FBtnModel.OnClick := @SelectModelClick;

  L := TLabel.Create(Self);
  L.Parent := FConfig;
  L.SetBounds(610, 8, 73, 20);
  L.Caption := 'Confiança:';
  FEdConfidence := TEdit.Create(Self);
  FEdConfidence.Parent := FConfig;
  FEdConfidence.SetBounds(685, 5, 70, 27);
  FEdConfidence.Text := '0.25';

  L := TLabel.Create(Self);
  L.Parent := FConfig;
  L.SetBounds(775, 8, 47, 20);
  L.Caption := 'imgsz:';
  FEdImageSize := TEdit.Create(Self);
  FEdImageSize.Parent := FConfig;
  FEdImageSize.SetBounds(825, 5, 70, 27);
  FEdImageSize.Text := '1024';

  L := TLabel.Create(Self);
  L.Parent := FConfig;
  L.SetBounds(610, 45, 70, 20);
  L.Caption := 'Device:';
  FEdDevice := TEdit.Create(Self);
  FEdDevice.Parent := FConfig;
  FEdDevice.SetBounds(685, 42, 210, 27);
  FEdDevice.Text := '';
  FEdDevice.Hint := 'Vazio = automático; exemplos: 0, cpu';
  FEdDevice.ShowHint := True;

  FRight := TPanel.Create(Self);
  FRight.Parent := Self;
  FRight.Align := alRight;
  FRight.Width := 385;
  FRight.Caption := '';
  FRight.BevelOuter := bvLowered;

  L := TLabel.Create(Self);
  L.Parent := FRight;
  L.SetBounds(10, 10, 260, 22);
  L.Caption := 'Resultado da contagem';
  L.Font.Style := [fsBold];
  L.Font.Size := 12;

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := FRight;
  FGrid.SetBounds(8, 40, 368, 290);
  FGrid.ColCount := 3;
  FGrid.RowCount := 2;
  FGrid.FixedRows := 1;
  FGrid.Cells[0,0] := 'Componente';
  FGrid.Cells[1,0] := 'Quantidade';
  FGrid.Cells[2,0] := 'Conf. média';
  FGrid.ColWidths[0] := 160;
  FGrid.ColWidths[1] := 80;
  FGrid.ColWidths[2] := 100;
  FGrid.Options := FGrid.Options - [goEditing];

  L := TLabel.Create(Self);
  L.Parent := FRight;
  L.SetBounds(10, 345, 300, 20);
  L.Caption := 'Relatório / observações';

  FMemo := TMemo.Create(Self);
  FMemo.Parent := FRight;
  FMemo.SetBounds(8, 370, 368, 290);
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.WordWrap := True;

  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.Height := 28;
  FBottom.BevelOuter := bvNone;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := FBottom;
  FStatus.Align := alClient;
  FStatus.SimplePanel := True;

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Center := True;
  FImage.Proportional := True;
  FImage.Stretch := True;

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
  FChatGPT.LoadConfigFromAppData('ChatGPT');

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

procedure TfrmMain.LoadImageClick(Sender: TObject);
begin
  if not FOpenImage.Execute then
    Exit;

  FCurrentImage := FOpenImage.FileName;
  FEdImage.Text := FCurrentImage;
  FImage.Picture.LoadFromFile(FCurrentImage);
  SetLength(FObjects, 0);
  SetLength(FSummaries, 0);
  UpdateGrid;
  FBtnExport.Enabled := False;
  FBtnAIReport.Enabled := False;
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
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := StrToFloatDef(StringReplace(Trim(FEdConfidence.Text), ',', '.', [rfReplaceAll]), 0.25, FS);
  if Result < 0 then Result := 0;
  if Result > 1 then Result := 1;
end;

function TfrmMain.ImageSizeValue: Integer;
begin
  Result := StrToIntDef(Trim(FEdImageSize.Text), 1024);
  if Result < 0 then Result := 0;
end;

function TfrmMain.NormalizeClass(const AName: string): string;
var
  S: string;
begin
  S := LowerCase(Trim(AName));
  if (S = 'rbc') or (S = 'red blood cell') or (S = 'red_blood_cell') then
    Exit('hemacia');
  if (S = 'wbc') or (S = 'white blood cell') or (S = 'white_blood_cell') then
    Exit('leucocito');
  if S = 'platelet' then
    Exit('plaqueta');
  if S = 'artifact' then
    Exit('artefato');
  Result := S;
end;

function TfrmMain.DisplayClass(const ACode: string): string;
begin
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

function TfrmMain.FindSummary(const ACode: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSummaries) do
    if FSummaries[I].Code = ACode then
      Exit(I);
  Result := -1;
end;

procedure TfrmMain.AddSummary(const ACode: string; AConfidence: Double);
var
  I: Integer;
begin
  I := FindSummary(ACode);
  if I < 0 then
  begin
    SetLength(FSummaries, Length(FSummaries) + 1);
    I := High(FSummaries);
    FSummaries[I].Code := ACode;
    FSummaries[I].DisplayName := DisplayClass(ACode);
    FSummaries[I].Count := 0;
    FSummaries[I].ConfidenceSum := 0;
  end;
  Inc(FSummaries[I].Count);
  FSummaries[I].ConfidenceSum := FSummaries[I].ConfidenceSum + AConfidence;
end;

procedure TfrmMain.BuildSummaries;
var
  I: Integer;
begin
  SetLength(FSummaries, 0);
  for I := 0 to High(FObjects) do
    AddSummary(NormalizeClass(FObjects[I].ClassName), FObjects[I].Confidence);
end;

procedure TfrmMain.UpdateGrid;
var
  I: Integer;
  Avg: Double;
begin
  FGrid.RowCount := Max(2, Length(FSummaries) + 1);
  for I := 1 to FGrid.RowCount - 1 do
  begin
    FGrid.Cells[0,I] := '';
    FGrid.Cells[1,I] := '';
    FGrid.Cells[2,I] := '';
  end;

  for I := 0 to High(FSummaries) do
  begin
    if FSummaries[I].Count > 0 then
      Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
    else
      Avg := 0;
    FGrid.Cells[0,I+1] := FSummaries[I].DisplayName;
    FGrid.Cells[1,I+1] := IntToStr(FSummaries[I].Count);
    FGrid.Cells[2,I+1] := FormatFloat('0.000', Avg);
  end;
end;

procedure TfrmMain.DrawDetections;
var
  Bmp: TBitmap;
  I: Integer;
  Code, LabelText: string;
begin
  if FCurrentImage = '' then Exit;

  FImage.Picture.LoadFromFile(FCurrentImage);
  if FImage.Picture.Graphic = nil then Exit;

  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(FImage.Picture.Graphic.Width, FImage.Picture.Graphic.Height);
    Bmp.Canvas.Draw(0, 0, FImage.Picture.Graphic);
    Bmp.Canvas.Brush.Style := bsClear;
    Bmp.Canvas.Pen.Width := 2;
    Bmp.Canvas.Font.Size := 9;

    for I := 0 to High(FObjects) do
    begin
      Code := NormalizeClass(FObjects[I].ClassName);
      Bmp.Canvas.Pen.Color := ColorForClass(Code);
      Bmp.Canvas.Font.Color := ColorForClass(Code);
      Bmp.Canvas.Rectangle(
        FObjects[I].X1, FObjects[I].Y1,
        FObjects[I].X2, FObjects[I].Y2
      );
      LabelText := DisplayClass(Code) + ' ' +
        FormatFloat('0%', FObjects[I].Confidence);
      Bmp.Canvas.TextOut(FObjects[I].X1 + 2, FObjects[I].Y1 + 2, LabelText);
    end;

    FImage.Picture.Assign(Bmp);
  finally
    Bmp.Free;
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
    S.Add('Imagem: ' + FCurrentImage);
    S.Add('Modelo: ' + FYolo.ModelPath);
    S.Add('Confiança mínima: ' + FormatFloat('0.000', FYolo.ConfidenceThreshold));
    if FYolo.ImageSize > 0 then
      S.Add('imgsz: ' + IntToStr(FYolo.ImageSize));
    S.Add('Objetos detectados: ' + IntToStr(Length(FObjects)));
    S.Add('');
    S.Add('CONTAGEM POR COMPONENTE');

    for I := 0 to High(FSummaries) do
    begin
      if FSummaries[I].Count > 0 then
        Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
      else
        Avg := 0;
      S.Add(Format('%s: %d | confiança média: %.3f',
        [FSummaries[I].DisplayName, FSummaries[I].Count, Avg]));
    end;

    S.Add('');
    S.Add('Observação: resultado de visão computacional para pesquisa/teste.');
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
    ShowMessage('Carregue uma imagem de lâmina antes de analisar.');
    Exit;
  end;

  if not FileExists(FEdModel.Text) then
  begin
    ShowMessage('Modelo não encontrado: ' + FEdModel.Text);
    Exit;
  end;

  if not FConnector.IsInitialized then
  begin
    ShowMessage('Python não está inicializado: ' + FConnector.LastError);
    Exit;
  end;

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
      SetStatus('Falha na análise.');
      Exit;
    end;

    BuildSummaries;
    UpdateGrid;
    DrawDetections;
    BuildDeterministicReport;

    FBtnExport.Enabled := True;
    FBtnAIReport.Enabled := True;
    SetStatus(Format('Análise concluída: %d objeto(s).', [Length(FObjects)]));
  finally
    FBtnAnalyze.Enabled := True;
    Screen.Cursor := crDefault;
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
    Root.Add('image', FCurrentImage);
    Root.Add('model', FYolo.ModelPath);
    Root.Add('confidence_threshold', FYolo.ConfidenceThreshold);
    Root.Add('imgsz', FYolo.ImageSize);
    Root.Add('total_objects', Length(FObjects));

    Arr := TJSONArray.Create;
    Root.Add('components', Arr);
    for I := 0 to High(FSummaries) do
    begin
      if FSummaries[I].Count > 0 then
        Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
      else
        Avg := 0;
      Item := TJSONObject.Create;
      Item.Add('code', FSummaries[I].Code);
      Item.Add('name', FSummaries[I].DisplayName);
      Item.Add('quantity', FSummaries[I].Count);
      Item.Add('mean_confidence', Avg);
      Arr.Add(Item);
    end;

    Dets := TJSONArray.Create;
    Root.Add('detections', Dets);
    for I := 0 to High(FObjects) do
    begin
      Det := TJSONObject.Create;
      Det.Add('class', NormalizeClass(FObjects[I].ClassName));
      Det.Add('confidence', FObjects[I].Confidence);
      Det.Add('x1', FObjects[I].X1);
      Det.Add('y1', FObjects[I].Y1);
      Det.Add('x2', FObjects[I].X2);
      Det.Add('y2', FObjects[I].Y2);
      Dets.Add(Det);
    end;

    S := TStringList.Create;
    try
      S.Text := Root.AsJSON;
      S.SaveToFile(AFileName);
    finally
      S.Free;
    end;
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
      if FSummaries[I].Count > 0 then
        Avg := FSummaries[I].ConfidenceSum / FSummaries[I].Count
      else
        Avg := 0;
      S.Add(FSummaries[I].Code + ';' + FSummaries[I].DisplayName + ';' +
        IntToStr(FSummaries[I].Count) + ';' + StringReplace(
          FormatFloat('0.000000', Avg), ',', '.', [rfReplaceAll]));
    end;
    S.SaveToFile(AFileName);
  finally
    S.Free;
  end;
end;

procedure TfrmMain.ExportText(const AFileName: string);
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Text := FMemo.Lines.Text;
    S.SaveToFile(AFileName);
  finally
    S.Free;
  end;
end;

procedure TfrmMain.ExportClick(Sender: TObject);
var
  Ext: string;
begin
  if Length(FSummaries) = 0 then
  begin
    ShowMessage('Execute uma análise antes de emitir o resultado.');
    Exit;
  end;

  FSaveReport.FileName := 'resultado_lamina_' +
    FormatDateTime('yyyymmdd_hhnnss', Now) + '.json';

  if not FSaveReport.Execute then Exit;

  Ext := LowerCase(ExtractFileExt(FSaveReport.FileName));
  if Ext = '.csv' then
    ExportCSV(FSaveReport.FileName)
  else if Ext = '.txt' then
    ExportText(FSaveReport.FileName)
  else
    ExportJSON(FSaveReport.FileName);

  SetStatus('Resultado salvo: ' + FSaveReport.FileName);
end;

procedure TfrmMain.AIReportClick(Sender: TObject);
var
  Prompt: string;
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
      FMemo.Lines.Add('');
      FMemo.Lines.Add('PARECER TEXTUAL DA IA');
      FMemo.Lines.Add(string(FChatGPT.Response));
      SetStatus('Parecer textual gerado.');
    end
    else
    begin
      ShowMessage('Não foi possível gerar o parecer. Verifique a configuração do TCHATGPT.');
      SetStatus('Falha no parecer de IA.');
    end;
  finally
    Screen.Cursor := crDefault;
  end;
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
  SetStatus('Pronto.');
end;

end.
