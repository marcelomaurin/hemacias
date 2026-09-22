unit camera_service;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics,
  {$IFDEF MSWINDOWS}
  Windows,
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

function ListConnectedCameras(out ACameras: TCameraDeviceArray): Boolean;
function CaptureCameraFrame(ACameraIndex, AWidth, AHeight: Integer;
  AParentHandle: THandle; const AOutputFile: string; out ACapturedPath: string): Boolean;

implementation

function ListConnectedCameras(out ACameras: TCameraDeviceArray): Boolean;
var
  Cap: TAICaptureSource;
  List: TStringList;
  I, DashPos: Integer;
  ItemStr: string;
begin
  Result := False;
  SetLength(ACameras, 0);
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

    if not Started then Exit;

    try
      // Tenta gravar direto no arquivo
      if Cap.CaptureToFile(AOutputFile) and FileExists(AOutputFile) then
      begin
        ACapturedPath := AOutputFile;
        Result := True;
      end
      else
      begin
        // Tenta capturar Bitmap e salvar
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
  finally
    Cap.Free;
  end;
end;

end.
