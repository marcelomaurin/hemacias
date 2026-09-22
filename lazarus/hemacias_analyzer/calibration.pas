unit calibration;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, measurement_types;

function CalculateTheoreticalScale(AObjectiveMag, AAdapterMag, ASensorPixelUM: Double): Double;
function CalibrateFromLine(AX1, AY1, AX2, AY2: Double; AKnownDistanceUM: Double): Double;

function CreateDefaultProfile(const AName: string; AObjMag: Double;
  AAdapterMag: Double = 1.0; ASensorPixelUM: Double = 3.45;
  ACalibratedScale: Double = 0.0): TOpticalProfile;

function ProfileToJSON(const P: TOpticalProfile): TJSONObject;
function JSONToProfile(AObj: TJSONObject): TOpticalProfile;

implementation

function CalculateTheoreticalScale(AObjectiveMag, AAdapterMag, ASensorPixelUM: Double): Double;
var
  TotalMag: Double;
begin
  TotalMag := Max(0.01, AObjectiveMag * AAdapterMag);
  Result := Max(0.00001, ASensorPixelUM / TotalMag);
end;

function CalibrateFromLine(AX1, AY1, AX2, AY2: Double; AKnownDistanceUM: Double): Double;
var
  DistPX: Double;
begin
  DistPX := Sqrt(Sqr(AX2 - AX1) + Sqr(AY2 - AY1));
  if (DistPX < 1.0) or (AKnownDistanceUM <= 0.0) then
    Result := 0.0
  else
    Result := AKnownDistanceUM / DistPX;
end;

function CreateDefaultProfile(const AName: string; AObjMag: Double;
  AAdapterMag: Double; ASensorPixelUM: Double;
  ACalibratedScale: Double): TOpticalProfile;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.ID := 0;
  Result.Name := AName;
  Result.CameraName := 'Microscópio USB';
  Result.CameraWidth := 1920;
  Result.CameraHeight := 1080;
  Result.ObjectiveMagnification := Max(1.0, AObjMag);
  Result.AdapterMagnification := Max(0.1, AAdapterMag);
  Result.SensorPixelSizeUM := Max(0.1, ASensorPixelUM);
  Result.TheoreticalPixelSizeUM := CalculateTheoreticalScale(Result.ObjectiveMagnification,
                                                            Result.AdapterMagnification,
                                                            Result.SensorPixelSizeUM);
  if ACalibratedScale > 0.00001 then
  begin
    Result.CalibratedPixelSizeUM := ACalibratedScale;
    Result.CalibrationMethod := 'STAGE_MICROMETER';
  end
  else
  begin
    Result.CalibratedPixelSizeUM := Result.TheoreticalPixelSizeUM;
    Result.CalibrationMethod := 'THEORETICAL';
  end;
  Result.Active := True;
  Result.CalibratedAt := Now;
end;

function ProfileToJSON(const P: TOpticalProfile): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', P.ID);
  Result.Add('name', P.Name);
  Result.Add('camera_name', P.CameraName);
  Result.Add('camera_width', P.CameraWidth);
  Result.Add('camera_height', P.CameraHeight);
  Result.Add('objective_magnification', P.ObjectiveMagnification);
  Result.Add('adapter_magnification', P.AdapterMagnification);
  Result.Add('sensor_pixel_size_um', P.SensorPixelSizeUM);
  Result.Add('theoretical_pixel_size_um', P.TheoreticalPixelSizeUM);
  Result.Add('calibrated_pixel_size_um', P.CalibratedPixelSizeUM);
  Result.Add('calibration_method', P.CalibrationMethod);
  Result.Add('calibration_reference_um', P.CalibrationReferenceUM);
  Result.Add('calibration_reference_px', P.CalibrationReferencePX);
  Result.Add('active', P.Active);
  Result.Add('calibrated_at', FormatDateTime('yyyy-mm-dd hh:nn:ss', P.CalibratedAt));
end;

function JSONToProfile(AObj: TJSONObject): TOpticalProfile;
var
  FS: TFormatSettings;

  function GetF(const AKey: string; ADef: Double): Double;
  var D: TJSONData;
  begin
    Result := ADef;
    if AObj = nil then Exit;
    D := AObj.Find(AKey);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Result := StrToFloatDef(StringReplace(D.AsString, ',', '.', [rfReplaceAll]), ADef, FS);
  end;

  function GetI(const AKey: string; ADef: Integer): Integer;
  var D: TJSONData;
  begin
    Result := ADef;
    if AObj = nil then Exit;
    D := AObj.Find(AKey);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Result := D.AsInteger;
  end;

  function GetS(const AKey, ADef: string): string;
  var D: TJSONData;
  begin
    Result := ADef;
    if AObj = nil then Exit;
    D := AObj.Find(AKey);
    if (D <> nil) and (D.JSONType <> jtNull) then
      Result := D.AsString;
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FillChar(Result, SizeOf(Result), 0);
  if AObj = nil then Exit;

  Result.ID := GetI('id', 0);
  Result.Name := GetS('name', 'Perfil Padrão');
  Result.CameraName := GetS('camera_name', 'Microscópio USB');
  Result.CameraWidth := GetI('camera_width', 1920);
  Result.CameraHeight := GetI('camera_height', 1080);
  Result.ObjectiveMagnification := GetF('objective_magnification', 40.0);
  Result.AdapterMagnification := GetF('adapter_magnification', 1.0);
  Result.SensorPixelSizeUM := GetF('sensor_pixel_size_um', 3.45);
  Result.TheoreticalPixelSizeUM := GetF('theoretical_pixel_size_um', 0.08625);
  Result.CalibratedPixelSizeUM := GetF('calibrated_pixel_size_um', 0.08625);
  Result.CalibrationMethod := GetS('calibration_method', 'THEORETICAL');
  Result.CalibrationReferenceUM := GetF('calibration_reference_um', 0.0);
  Result.CalibrationReferencePX := GetF('calibration_reference_px', 0.0);
  Result.Active := True;
  Result.CalibratedAt := Now;
end;

end.
