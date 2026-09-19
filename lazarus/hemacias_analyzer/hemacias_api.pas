unit hemacias_api;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, opensslsockets, fpjson, jsonparser, base64;

type
  { THemaciasApiClient }

  THemaciasApiClient = class
  private
    FBaseURL: string;
    FApiKey: string;
    FLastError: string;
    function Endpoint(const AAction: string): string;
    function RequestJSON(const AAction: string; AData: TJSONData;
      AUseGet: Boolean = False; const AQuery: string = ''): TJSONData;
    function ReadFileBase64(const AFileName: string): string;
  public
    constructor Create(const ABaseURL, AApiKey: string);

    property BaseURL: string read FBaseURL write FBaseURL;
    property ApiKey: string read FApiKey write FApiKey;
    property LastError: string read FLastError;

    function GetConfig(ASampleID: Int64 = 0): TJSONObject;
    function UpsertPatient(const AName, AExternalID: string): Int64;
    function CreateSample(APatientID: Int64; const ASampleCode,
      AProtocolCode: string): Int64;
    function CreateCount(APayload: TJSONObject; const AImageFile: string;
      out ACountID, AImageID, AFieldID: Int64; out AFieldNo: Integer): Boolean;
  end;

implementation

constructor THemaciasApiClient.Create(const ABaseURL, AApiKey: string);
begin
  inherited Create;
  FBaseURL := ExcludeTrailingPathDelimiter(Trim(ABaseURL));
  FApiKey := Trim(AApiKey);
  FLastError := '';
end;

function THemaciasApiClient.Endpoint(const AAction: string): string;
begin
  Result := FBaseURL + '/api.php?action=' + AAction;
end;

function THemaciasApiClient.RequestJSON(const AAction: string; AData: TJSONData;
  AUseGet: Boolean; const AQuery: string): TJSONData;
var
  HTTP: TFPHttpClient;
  Response: TStringStream;
  Body: TStringStream;
  URL, Text: string;
begin
  Result := nil;
  FLastError := '';

  if FBaseURL = '' then
  begin
    FLastError := 'URL da API não configurada.';
    Exit;
  end;
  if FApiKey = '' then
  begin
    FLastError := 'API key não configurada.';
    Exit;
  end;

  HTTP := TFPHttpClient.Create(nil);
  Response := TStringStream.Create('');
  Body := nil;
  try
    HTTP.AddHeader('X-API-Key', FApiKey);
    HTTP.AddHeader('Accept', 'application/json');

    URL := Endpoint(AAction);
    if AQuery <> '' then
      URL := URL + '&' + AQuery;

    try
      if AUseGet then
        HTTP.Get(URL, Response)
      else
      begin
        HTTP.AddHeader('Content-Type', 'application/json; charset=utf-8');
        if AData <> nil then
          Body := TStringStream.Create(AData.AsJSON)
        else
          Body := TStringStream.Create('{}');
        HTTP.RequestBody := Body;
        HTTP.Post(URL, Response);
        HTTP.RequestBody := nil;
      end;
    except
      on E: Exception do
      begin
        FLastError := 'Falha HTTP: ' + E.Message;
        Exit;
      end;
    end;

    Text := Trim(Response.DataString);
    if Text = '' then
    begin
      FLastError := 'Servidor retornou resposta vazia.';
      Exit;
    end;

    try
      Result := GetJSON(Text);
    except
      on E: Exception do
      begin
        FLastError := 'JSON inválido retornado pela API: ' + E.Message;
        Result := nil;
      end;
    end;
  finally
    Body.Free;
    Response.Free;
    HTTP.Free;
  end;
end;

function THemaciasApiClient.GetConfig(ASampleID: Int64): TJSONObject;
var
  Req: TJSONObject;
  Data: TJSONData;
begin
  Result := nil;
  Req := TJSONObject.Create;
  try
    if ASampleID > 0 then
      Req.Add('sample_id', ASampleID);
    Data := RequestJSON('config', Req);
  finally
    Req.Free;
  end;

  if Data = nil then Exit;
  if not (Data is TJSONObject) then
  begin
    FLastError := 'Resposta de config não é objeto JSON.';
    Data.Free;
    Exit;
  end;

  Result := TJSONObject(Data);
  if not Result.Get('ok', False) then
  begin
    FLastError := Result.Get('error', 'Falha ao consultar configuração.');
    FreeAndNil(Result);
  end;
end;

function THemaciasApiClient.UpsertPatient(const AName, AExternalID: string): Int64;
var
  Req: TJSONObject;
  Data: TJSONData;
  Obj: TJSONObject;
  IDData: TJSONData;
begin
  Result := 0;
  Req := TJSONObject.Create;
  try
    Req.Add('name', AName);
    if Trim(AExternalID) <> '' then
      Req.Add('external_id', AExternalID);
    Data := RequestJSON('patient_upsert', Req);
  finally
    Req.Free;
  end;

  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then
    begin
      FLastError := 'Resposta inválida ao cadastrar paciente.';
      Exit;
    end;
    Obj := TJSONObject(Data);
    if not Obj.Get('ok', False) then
    begin
      FLastError := Obj.Get('error', 'Falha ao cadastrar paciente.');
      Exit;
    end;
    IDData := Obj.Find('patient_id');
    if IDData <> nil then
      Result := StrToInt64Def(IDData.AsString, 0);
  finally
    Data.Free;
  end;
end;

function THemaciasApiClient.CreateSample(APatientID: Int64;
  const ASampleCode, AProtocolCode: string): Int64;
var
  Req: TJSONObject;
  Data: TJSONData;
  Obj: TJSONObject;
  IDData: TJSONData;
begin
  Result := 0;
  Req := TJSONObject.Create;
  try
    Req.Add('patient_id', APatientID);
    Req.Add('sample_code', ASampleCode);
    if Trim(AProtocolCode) <> '' then
      Req.Add('protocol_code', AProtocolCode);
    Data := RequestJSON('sample_create', Req);
  finally
    Req.Free;
  end;

  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then
    begin
      FLastError := 'Resposta inválida ao criar amostra.';
      Exit;
    end;
    Obj := TJSONObject(Data);
    if not Obj.Get('ok', False) then
    begin
      FLastError := Obj.Get('error', 'Falha ao criar amostra.');
      Exit;
    end;
    IDData := Obj.Find('sample_id');
    if IDData <> nil then
      Result := StrToInt64Def(IDData.AsString, 0);
  finally
    Data.Free;
  end;
end;

function THemaciasApiClient.ReadFileBase64(const AFileName: string): string;
var
  Stream: TFileStream;
  Raw: RawByteString;
begin
  Result := '';
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Raw, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Raw[1], Stream.Size);
    Result := EncodeStringBase64(Raw);
  finally
    Stream.Free;
  end;
end;

function THemaciasApiClient.CreateCount(APayload: TJSONObject;
  const AImageFile: string; out ACountID, AImageID, AFieldID: Int64;
  out AFieldNo: Integer): Boolean;
var
  Req: TJSONObject;
  Data: TJSONData;
  Obj: TJSONObject;
  D: TJSONData;

  function JsonInt64(const AName: string): Int64;
  begin
    Result := 0;
    D := Obj.Find(AName);
    if D <> nil then
      Result := StrToInt64Def(D.AsString, 0);
  end;

begin
  Result := False;
  ACountID := 0;
  AImageID := 0;
  AFieldID := 0;
  AFieldNo := 0;

  Req := TJSONObject(GetJSON(APayload.AsJSON));
  try
    if (AImageFile <> '') and FileExists(AImageFile) then
    begin
      Req.Add('image_name', ExtractFileName(AImageFile));
      Req.Add('image_base64', ReadFileBase64(AImageFile));
    end;

    Data := RequestJSON('count_create', Req);
  finally
    Req.Free;
  end;

  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then
    begin
      FLastError := 'Resposta inválida ao enviar contagem.';
      Exit;
    end;

    Obj := TJSONObject(Data);
    if not Obj.Get('ok', False) then
    begin
      FLastError := Obj.Get('error', 'Falha ao enviar contagem.');
      Exit;
    end;

    ACountID := JsonInt64('count_id');
    AImageID := JsonInt64('image_id');
    AFieldID := JsonInt64('field_id');
    AFieldNo := Integer(JsonInt64('field_no'));
    Result := ACountID > 0;
  finally
    Data.Free;
  end;
end;

end.
