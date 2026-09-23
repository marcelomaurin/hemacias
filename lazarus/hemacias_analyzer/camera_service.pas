unit camera_service;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Process, fpjson, jsonparser,
  {$IFDEF MSWINDOWS}
  Windows, ActiveX, ComObj, Variants,
  {$ENDIF}
  aicapturesource, aicamera_backend, aicamera_vfw;

type
  TCameraDeviceInfo = record
    Index: Integer;
    Name: string;
    Width: Integer;
    Height: Integer;
  end;
  TCameraDeviceArray = array of TCameraDeviceInfo;

  TCameraResolution = record
    Width: Integer;
    Height: Integer;
    FPS: Double;
  end;
  TCameraResolutionArray = array of TCameraResolution;

function ListConnectedCameras(out ACameras: TCameraDeviceArray): Boolean;
function ListCameraResolutions(ACameraIndex: Integer;
  out AResolutions: TCameraResolutionArray; out ASource: string): Boolean; overload;
function ListCameraResolutions(ACameraIndex: Integer;
  out AResolutions: TCameraResolutionArray): Boolean; overload;
function GetBestCameraResolution(ACameraIndex: Integer;
  out AWidth: Integer; out AHeight: Integer; out AFPS: Double): Boolean;
function ResolutionMegapixels(AWidth, AHeight: Integer): Double;


function CaptureCameraFrame(ACameraIndex, AWidth, AHeight: Integer;
  AParentHandle: THandle; const AOutputFile: string; out ACapturedPath: string): Boolean;

implementation

function FindCameraScript: string; forward;

function ResolutionMegapixels(AWidth, AHeight: Integer): Double;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    Result := 0.0
  else
    Result := (Double(AWidth) * Double(AHeight)) / 1000000.0;
end;

procedure SortAndFilterResolutions(var ARes: TCameraResolutionArray);
var
  I, J, K, N: Integer;
  Tmp: TCameraResolution;
  Duplicate: Boolean;
  Filtered: TCameraResolutionArray;
begin
  N := Length(ARes);
  if N <= 0 then Exit;

  // 1. Remove modos invalidos (<= 0)
  SetLength(Filtered, 0);
  for I := 0 to N - 1 do
  begin
    if (ARes[I].Width > 0) and (ARes[I].Height > 0) then
    begin
      Duplicate := False;
      for J := 0 to High(Filtered) do
      begin
        if (Filtered[J].Width = ARes[I].Width) and (Filtered[J].Height = ARes[I].Height) then
        begin
          Duplicate := True;
          // Mantem preferencialmente o maior FPS
          if ARes[I].FPS > Filtered[J].FPS then
            Filtered[J].FPS := ARes[I].FPS;
          Break;
        end;
      end;
      if not Duplicate then
      begin
        SetLength(Filtered, Length(Filtered) + 1);
        Filtered[High(Filtered)] := ARes[I];
      end;
    end;
  end;

  // 2. Ordena por quantidade total de pixels (Width * Height) do menor para o maior
  for I := 0 to High(Filtered) - 1 do
  begin
    for J := I + 1 to High(Filtered) do
    begin
      if (Int64(Filtered[J].Width) * Int64(Filtered[J].Height) < Int64(Filtered[I].Width) * Int64(Filtered[I].Height)) or
         ((Int64(Filtered[J].Width) * Int64(Filtered[J].Height) = Int64(Filtered[I].Width) * Int64(Filtered[I].Height)) and
          (Filtered[J].FPS < Filtered[I].FPS)) then
      begin
        Tmp := Filtered[I];
        Filtered[I] := Filtered[J];
        Filtered[J] := Tmp;
      end;
    end;
  end;

  ARes := Filtered;
end;

procedure SetGenericResolutionPresets(out AResolutions: TCameraResolutionArray);
const
  Presets: array[0..13, 0..1] of Integer = (
    (640, 480),
    (800, 600),
    (1024, 768),
    (1280, 720),
    (1280, 960),
    (1280, 1024),
    (1600, 1200),
    (1920, 1080),
    (1920, 1200),
    (2048, 1536),
    (2560, 1440),
    (2592, 1944),
    (3264, 2448),
    (3840, 2160)
  );
var
  I: Integer;
begin
  SetLength(AResolutions, Length(Presets));
  for I := 0 to High(Presets) do
  begin
    AResolutions[I].Width := Presets[I, 0];
    AResolutions[I].Height := Presets[I, 1];
    AResolutions[I].FPS := 30.0;
  end;
  SortAndFilterResolutions(AResolutions);
end;

function ListResolutionsViaPython(ACameraIndex: Integer;
  out AResolutions: TCameraResolutionArray; out ASource: string): Boolean;
var
  ScriptPath, OutStr: string;
  Args: array of string;
  JSON: TJSONData;
  Obj, ResObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := False;
  SetLength(AResolutions, 0);
  ASource := 'GENERIC_PRESET';
  ScriptPath := FindCameraScript;
  if (ScriptPath = '') or not FileExists(ScriptPath) then Exit;

  SetLength(Args, 4);
  Args[0] := ScriptPath;
  Args[1] := '--resolutions';
  Args[2] := '--camera';
  Args[3] := IntToStr(ACameraIndex);

  OutStr := '';
  if not RunCommand('python', Args, OutStr) then
    if not RunCommand('python3', Args, OutStr) then
      if not RunCommand('py', Args, OutStr) then
        Exit;

  try
    JSON := GetJSON(OutStr);
    try
      if (JSON <> nil) and (JSON is TJSONObject) then
      begin
        Obj := TJSONObject(JSON);
        if Obj.Get('ok', False) and (Obj.Find('resolutions') is TJSONArray) then
        begin
          Arr := TJSONArray(Obj.Find('resolutions'));
          SetLength(AResolutions, Arr.Count);
          for I := 0 to Arr.Count - 1 do
          begin
            ResObj := TJSONObject(Arr[I]);
            AResolutions[I].Width := ResObj.Get('width', 0);
            AResolutions[I].Height := ResObj.Get('height', 0);
            AResolutions[I].FPS := ResObj.Get('fps', 30.0);
          end;
          SortAndFilterResolutions(AResolutions);
          if Length(AResolutions) > 0 then
          begin
            ASource := Obj.Get('source', 'DEVICE_REPORTED');
            Result := True;
          end;
        end;
      end;
    finally
      JSON.Free;
    end;
  except
    Result := False;
  end;
end;

function ListCameraResolutions(ACameraIndex: Integer;
  out AResolutions: TCameraResolutionArray; out ASource: string): Boolean;
begin
  // 1. Tenta consulta direta via backend do dispositivo (OpenCV/DirectShow via script Python)
  if ListResolutionsViaPython(ACameraIndex, AResolutions, ASource) then
  begin
    Result := True;
    Exit;
  end;

  // 2. Se a consulta aos modos do driver falhar, usa os presets genéricos padronizados
  SetGenericResolutionPresets(AResolutions);
  ASource := 'GENERIC_PRESET';
  Result := True;
end;

function ListCameraResolutions(ACameraIndex: Integer;
  out AResolutions: TCameraResolutionArray): Boolean;
var
  DummySource: string;
begin
  Result := ListCameraResolutions(ACameraIndex, AResolutions, DummySource);
end;

function GetBestCameraResolution(ACameraIndex: Integer;
  out AWidth: Integer; out AHeight: Integer; out AFPS: Double): Boolean;
var
  ResList: TCameraResolutionArray;
  BestPixels, CurPixels: Int64;
  I: Integer;
begin
  AWidth := 1920;
  AHeight := 1080;
  AFPS := 30.0;
  Result := False;

  if not ListCameraResolutions(ACameraIndex, ResList) or (Length(ResList) = 0) then
    Exit;

  BestPixels := -1;
  for I := 0 to High(ResList) do
  begin
    CurPixels := Int64(ResList[I].Width) * Int64(ResList[I].Height);
    if (CurPixels > BestPixels) or
       ((CurPixels = BestPixels) and (ResList[I].FPS > AFPS)) then
    begin
      BestPixels := CurPixels;
      AWidth := ResList[I].Width;
      AHeight := ResList[I].Height;
      AFPS := ResList[I].FPS;
      Result := True;
    end;
  end;
end;


const
  CLSID_SystemDeviceEnum: TGUID = '{62BE5D10-60EB-11d0-BD3B-00A0C911CE86}';
  CLSID_VideoInputDeviceCategory: TGUID = '{860BB310-5D01-11d0-BD3B-00A0C911CE86}';
  IID_ICreateDevEnum: TGUID = '{29840822-5B84-11D0-BD3B-00A0C911CE86}';

type
  ICreateDevEnum = interface(IUnknown)
    ['{29840822-5B84-11D0-BD3B-00A0C911CE86}']
    function CreateClassEnumerator(const clsidDeviceClass: TGUID;
      out ppEnumMoniker: IEnumMoniker; dwFlags: DWORD): HResult; stdcall;
  end;

  IPropertyBag = interface(IUnknown)
    ['{55272A00-42CB-11CE-8135-00AA004BB851}']
    function Read(pszPropName: POleStr; var pVar: OleVariant; pErrorLog: Pointer): HResult; stdcall;
    function Write(pszPropName: POleStr; var pVar: OleVariant): HResult; stdcall;
  end;

function FindCameraScript: string;
var
  Base: string;
begin
  Result := '';
  Base := ExtractFilePath(ParamStr(0));
  if FileExists(Base + 'python' + PathDelim + 'camera_capture.py') then
    Result := Base + 'python' + PathDelim + 'camera_capture.py'
  else if FileExists(Base + '..' + PathDelim + 'python' + PathDelim + 'camera_capture.py') then
    Result := Base + '..' + PathDelim + 'python' + PathDelim + 'camera_capture.py'
  else if FileExists(Base + '..' + PathDelim + '..' + PathDelim + 'python' + PathDelim + 'camera_capture.py') then
    Result := Base + '..' + PathDelim + '..' + PathDelim + 'python' + PathDelim + 'camera_capture.py'
  else if FileExists('P:\maurinsoft\hemacias\python\camera_capture.py') then
    Result := 'P:\maurinsoft\hemacias\python\camera_capture.py';
end;

function EnumerateDirectShowCameras(out ACameras: TCameraDeviceArray): Boolean;
var
  HR: HResult;
  NeedUninit: Boolean;
  DevEnum: ICreateDevEnum;
  EnumMoniker: IEnumMoniker;
  Moniker: IMoniker;
  Fetched: ULONG;
  PropBagObj: IUnknown;
  PropBag: IPropertyBag;
  VarName: OleVariant;
  CamName: string;
  Count: Integer;
begin
  Result := False;
  SetLength(ACameras, 0);
  NeedUninit := False;
  try
    HR := CoInitialize(nil);
    NeedUninit := Succeeded(HR);

    HR := CoCreateInstance(CLSID_SystemDeviceEnum, nil, CLSCTX_INPROC_SERVER,
      IID_ICreateDevEnum, DevEnum);
    if Succeeded(HR) and (DevEnum <> nil) then
    begin
      HR := DevEnum.CreateClassEnumerator(CLSID_VideoInputDeviceCategory, EnumMoniker, 0);
      if Succeeded(HR) and (EnumMoniker <> nil) then
      begin
        Count := 0;
        while EnumMoniker.Next(1, Moniker, Fetched) = S_OK do
        begin
          try
            HR := Moniker.BindToStorage(nil, nil, IPropertyBag, PropBagObj);
            if Succeeded(HR) and Supports(PropBagObj, IPropertyBag, PropBag) then
            begin
              VarClear(VarName);
              if Succeeded(PropBag.Read('FriendlyName', VarName, nil)) then
              begin
                CamName := Trim(String(VarName));
                if CamName <> '' then
                begin
                  SetLength(ACameras, Count + 1);
                  ACameras[Count].Index := Count;
                  ACameras[Count].Name := CamName;
                  ACameras[Count].Width := 1920;
                  ACameras[Count].Height := 1080;
                  Inc(Count);
                end;
              end;
            end;
          finally
            Moniker := nil;
            PropBagObj := nil;
            PropBag := nil;
          end;
        end;
      end;
    end;
  except
  end;

  if NeedUninit then
    try CoUninitialize; except end;

  Result := Length(ACameras) > 0;
end;

function ListCamerasViaPython(out ACameras: TCameraDeviceArray): Boolean;
var
  ScriptPath, OutStr: string;
  JSON: TJSONData;
  Obj, CamObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := False;
  SetLength(ACameras, 0);
  ScriptPath := FindCameraScript;
  if (ScriptPath = '') or not FileExists(ScriptPath) then Exit;

  OutStr := '';
  if not RunCommand('python', [ScriptPath, '--list'], OutStr) then
    if not RunCommand('python3', [ScriptPath, '--list'], OutStr) then
      if not RunCommand('py', [ScriptPath, '--list'], OutStr) then
        Exit;

  try
    JSON := GetJSON(OutStr);
    try
      if (JSON <> nil) and (JSON is TJSONObject) then
      begin
        Obj := TJSONObject(JSON);
        if Obj.Get('ok', False) and (Obj.Find('cameras') is TJSONArray) then
        begin
          Arr := TJSONArray(Obj.Find('cameras'));
          SetLength(ACameras, Arr.Count);
          for I := 0 to Arr.Count - 1 do
          begin
            CamObj := TJSONObject(Arr[I]);
            ACameras[I].Index := CamObj.Get('index', I);
            ACameras[I].Name := CamObj.Get('name', 'Camera ' + IntToStr(I));
            ACameras[I].Width := CamObj.Get('width', 1920);
            ACameras[I].Height := CamObj.Get('height', 1080);
          end;
          Result := Length(ACameras) > 0;
        end;
      end;
    finally
      JSON.Free;
    end;
  except
    Result := False;
  end;
end;

function CaptureViaPython(ACameraIndex, AWidth, AHeight: Integer; const AOutputFile: string): Boolean;
var
  ScriptPath, OutStr: string;
  Args: array of string;
begin
  Result := False;
  ScriptPath := FindCameraScript;
  if (ScriptPath = '') or not FileExists(ScriptPath) then Exit;

  SetLength(Args, 10);
  Args[0] := ScriptPath;
  Args[1] := '--capture';
  Args[2] := '--camera';
  Args[3] := IntToStr(ACameraIndex);
  Args[4] := '--width';
  Args[5] := IntToStr(AWidth);
  Args[6] := '--height';
  Args[7] := IntToStr(AHeight);
  Args[8] := '--output';
  Args[9] := AOutputFile;

  OutStr := '';
  if RunCommand('python', Args, OutStr) and FileExists(AOutputFile) then
    Result := True
  else if RunCommand('python3', Args, OutStr) and FileExists(AOutputFile) then
    Result := True
  else if RunCommand('py', Args, OutStr) and FileExists(AOutputFile) then
    Result := True;
end;

function ListConnectedCameras(out ACameras: TCameraDeviceArray): Boolean;
var
  Cap: TAICaptureSource;
  List: TStringList;
  I, DashPos: Integer;
  ItemStr: string;
begin
  Result := False;
  SetLength(ACameras, 0);

  // 1. Tenta listar via Python com nomes amigaveis
  if ListCamerasViaPython(ACameras) then
  begin
    Result := True;
    Exit;
  end;

  // 2. Método principal Lazarus: TAICaptureSource
  Cap := TAICaptureSource.Create(nil);
  try
    List := Cap.ListAvailableCameras;
    try
      if (List <> nil) and (List.Count > 0) then
      begin
        SetLength(ACameras, List.Count);
        for I := 0 to List.Count - 1 do
        begin
          ItemStr := Trim(List[I]);
          ACameras[I].Index := I;
          DashPos := Pos(' - ', ItemStr);
          if DashPos > 0 then
          begin
            ACameras[I].Index := StrToIntDef(Trim(Copy(ItemStr, 1, DashPos - 1)), I);
            ACameras[I].Name := Trim(Copy(ItemStr, DashPos + 3, Length(ItemStr)));
          end
          else
            ACameras[I].Name := ItemStr;

          ACameras[I].Width := 1920;
          ACameras[I].Height := 1080;
        end;
        Result := Length(ACameras) > 0;
      end;
    finally
      List.Free;
    end;
  finally
    Cap.Free;
  end;

  if Result then Exit;

  // 3. Método de contingência: DirectShow COM nativo direto
  {$IFDEF MSWINDOWS}
  if EnumerateDirectShowCameras(ACameras) then
  begin
    Result := True;
    Exit;
  end;
  {$ENDIF}
end;

function CaptureCameraFrame(ACameraIndex, AWidth, AHeight: Integer;
  AParentHandle: THandle; const AOutputFile: string; out ACapturedPath: string): Boolean;
var
  Cap: TAICaptureSource;
  Bmp: Graphics.TBitmap;
  ParentH: THandle;
  Started: Boolean;
begin
  Result := False;
  ACapturedPath := '';

  // 1. Para câmeras secundárias (índice > 0) ou quando o script Python estiver disponível:
  // No Windows, o backend VFW não suporta índices adicionais (só existe driver 0).
  // Além disso, o Python OpenCV captura em alta resolução nativa (1600x1200 / 1920x1080).
  if (ACameraIndex > 0) or (FindCameraScript <> '') then
  begin
    if CaptureViaPython(ACameraIndex, AWidth, AHeight, AOutputFile) and FileExists(AOutputFile) then
    begin
      ACapturedPath := AOutputFile;
      Result := True;
      Exit;
    end;
  end;

  // 2. Tenta captura via TAICaptureSource (CHATGPT / VFW) para índice 0
  Cap := TAICaptureSource.Create(nil);
  try
    Cap.SourceKind := cskCameraLocal;
    Cap.CameraIndex := ACameraIndex;
    Cap.Width := AWidth;
    Cap.Height := AHeight;
    Cap.AutoDeleteTempFiles := False;

    {$IFDEF MSWINDOWS}
    if AParentHandle <> 0 then
      ParentH := AParentHandle
    else
      ParentH := Windows.GetDesktopWindow;
    {$ELSE}
    ParentH := AParentHandle;
    {$ENDIF}

    Cap.PreviewHandle := ParentH;
    Cap.PreviewEnabled := False;

    Started := Cap.StartCapture;
    if not Started then
    begin
      Cap.PreviewEnabled := True;
      Started := Cap.StartCapture;
    end;

    if Started then
    begin
      try
        if Cap.CaptureToFile(AOutputFile) and FileExists(AOutputFile) then
        begin
          ACapturedPath := AOutputFile;
          Result := True;
        end
        else
        begin
          Bmp := nil;
          if Cap.CaptureToBitmap(Bmp) and Assigned(Bmp) then
          begin
            try
              Bmp.SaveToFile(AOutputFile);
              if FileExists(AOutputFile) then
              begin
                ACapturedPath := AOutputFile;
                Result := True;
              end;
            finally
              Bmp.Free;
            end;
          end;
        end;
      finally
        Cap.StopCapture;
      end;
    end;
  finally
    Cap.Free;
  end;

  if Result then Exit;

  // 3. Fallback de contingência final: Python OpenCV
  if CaptureViaPython(ACameraIndex, AWidth, AHeight, AOutputFile) and FileExists(AOutputFile) then
  begin
    ACapturedPath := AOutputFile;
    Result := True;
  end;
end;

end.
