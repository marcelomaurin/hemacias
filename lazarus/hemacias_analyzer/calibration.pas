unit calibration;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, measurement_types;

// Escala óptica teórica (base física do sensor e ampliação da objetiva/adaptador)
function CalculateTheoreticalScale(AObjectiveMag, AAdapterMag, ASensorPixelUM: Double): Double;
function CalculateResizeFactor(AAcquisitionSize, AAnalysisSize: Integer): Double;
procedure CalculateEffectiveScale(const P: TOpticalProfile; out AScaleX, AScaleY: Double);

function GetMeasurementScaleX(const P: TOpticalProfile): Double;
function GetMeasurementScaleY(const P: TOpticalProfile): Double;

function CalibrateFromLine(AX1, AY1, AX2, AY2: Double; AKnownDistanceUM: Double): Double;

function CreateDefaultProfile(const AName: string; AObjMag: Double;
  AAdapterMag: Double = 1.0; ASensorPixelUM: Double = 3.45;
  ACalibratedScale: Double = 0.0;
  AAcquisitionW: Integer = 1920; AAcquisitionH: Integer = 1080;
  AAnalysisW: Integer = 1920; AAnalysisH: Integer = 1080): TOpticalProfile;

function ProfileToJSON(const P: TOpticalProfile): TJSONObject;
function JSONToProfile(AObj: TJSONObject): TOpticalProfile;

implementation

{ Documentação do cálculo teórico:
  Calcula a escala no plano do sensor dividida pela magnificação óptica total:
  TheoreticalOpticalScale = sensor_pixel_um / (objective * adapter)
  Representa a escala óptica teórica em µm/px antes de qualquer resize ou pós-processamento digital.
  A ocular visual NÃO faz parte do caminho óptico da câmera digital. }
function CalculateTheoreticalScale(AObjectiveMag, AAdapterMag, ASensorPixelUM: Double): Double;
var
  TotalMag: Double;
begin
  TotalMag := Max(0.01, AObjectiveMag * AAdapterMag);
  Result := Max(0.00001, ASensorPixelUM / TotalMag);
end;

function CalculateResizeFactor(AAcquisitionSize, AAnalysisSize: Integer): Double;
begin
  if (AAcquisitionSize <= 0) or (AAnalysisSize <= 0) then
    Result := 1.0
  else
    Result := AAcquisitionSize / AAnalysisSize;
end;

procedure CalculateEffectiveScale(const P: TOpticalProfile; out AScaleX, AScaleY: Double);
var
  RFX, RFY: Double;
begin
  RFX := CalculateResizeFactor(P.AcquisitionWidthPX, P.AnalysisWidthPX);
  RFY := CalculateResizeFactor(P.AcquisitionHeightPX, P.AnalysisHeightPX);
  AScaleX := P.TheoreticalPixelSizeUM * RFX;
  AScaleY := P.TheoreticalPixelSizeUM * RFY;
end;

{ Hierarquia de calibração:
  1. STAGE_MICROMETER (calibração metrológica com micrômetro de lâmina)
  2. SCALE_BAR (calibração por barra de escala física conhecida)
  3. MANUAL (definição manual calibrada)
  4. THEORETICAL / ESTIMATED_REFERENCE (estimativa óptica teórica / referência estimada) }
function GetMeasurementScaleX(const P: TOpticalProfile): Double;
begin
  if ((P.CalibrationMethod = 'STAGE_MICROMETER') or
      (P.CalibrationMethod = 'SCALE_BAR') or
      (P.CalibrationMethod = 'MANUAL')) and (P.CalibratedPixelSizeUM > 0.00001) then
    Result := P.CalibratedPixelSizeUM
  else if P.EffectivePixelSizeXUM > 0.00001 then
    Result := P.EffectivePixelSizeXUM
  else if P.TheoreticalPixelSizeUM > 0.00001 then
    Result := P.TheoreticalPixelSizeUM
  else
    Result := 0.08625;
end;

function GetMeasurementScaleY(const P: TOpticalProfile): Double;
begin
  if ((P.CalibrationMethod = 'STAGE_MICROMETER') or
      (P.CalibrationMethod = 'SCALE_BAR') or
      (P.CalibrationMethod = 'MANUAL')) and (P.CalibratedPixelSizeUM > 0.00001) then
    Result := P.CalibratedPixelSizeUM
  else if P.EffectivePixelSizeYUM > 0.00001 then
    Result := P.EffectivePixelSizeYUM
  else if P.TheoreticalPixelSizeUM > 0.00001 then
    Result := P.TheoreticalPixelSizeUM
  else
    Result := 0.08625;
end;

function CalibrateFromLine(AX1, AY1, AX2, AY2: Double; AKnownDistanceUM: Double): Double;
var
  DistPX: Double;
begin
  DistPX := Sqrt(Sqr(AX2 - AX1) + Sqr(AY2 - AY1));
  if (DistPX < 2.0) or (AKnownDistanceUM <= 0.0) then
    Result := 0.0
  else
    Result := AKnownDistanceUM / DistPX;
end;

function CreateDefaultProfile(const AName: string; AObjMag: Double;
  AAdapterMag: Double; ASensorPixelUM: Double;
  ACalibratedScale: Double;
  AAcquisitionW: Integer; AAcquisitionH: Integer;
  AAnalysisW: Integer; AAnalysisH: Integer): TOpticalProfile;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.ID := 0;
  Result.Name := AName;
  Result.CameraName := 'Microscópio USB (Padrão Provisório)';
  Result.CameraWidth := 1920;
  Result.CameraHeight := 1080;
  Result.ObjectiveMagnification := Max(1.0, AObjMag);
  Result.AdapterMagnification := Max(0.1, AAdapterMag);
  Result.SensorPixelSizeUM := Max(0.1, ASensorPixelUM);
  Result.TheoreticalPixelSizeUM := CalculateTheoreticalScale(Result.ObjectiveMagnification,
                                                            Result.AdapterMagnification,
                                                            Result.SensorPixelSizeUM);

  Result.AcquisitionWidthPX := Max(1, AAcquisitionW);
  Result.AcquisitionHeightPX := Max(1, AAcquisitionH);
  Result.AnalysisWidthPX := Max(1, AAnalysisW);
  Result.AnalysisHeightPX := Max(1, AAnalysisH);
  Result.ResizeFactorX := CalculateResizeFactor(Result.AcquisitionWidthPX, Result.AnalysisWidthPX);
  Result.ResizeFactorY := CalculateResizeFactor(Result.AcquisitionHeightPX, Result.AnalysisHeightPX);
  Result.RequestedWidthPX := Result.AcquisitionWidthPX;
  Result.RequestedHeightPX := Result.AcquisitionHeightPX;
  Result.CameraFPS := 30.0;
  Result.ResolutionSource := 'DEVICE_REPORTED';
  CalculateEffectiveScale(Result, Result.EffectivePixelSizeXUM, Result.EffectivePixelSizeYUM);

  if ACalibratedScale > 0.00001 then
  begin
    Result.CalibratedPixelSizeUM := ACalibratedScale;
    Result.CalibrationMethod := 'STAGE_MICROMETER';
  end
  else
  begin
    Result.CalibratedPixelSizeUM := Result.EffectivePixelSizeXUM;
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
  Result.Add('acquisition_width_px', P.AcquisitionWidthPX);
  Result.Add('acquisition_height_px', P.AcquisitionHeightPX);
  Result.Add('analysis_width_px', P.AnalysisWidthPX);
  Result.Add('analysis_height_px', P.AnalysisHeightPX);
  Result.Add('resize_factor_x', P.ResizeFactorX);
  Result.Add('resize_factor_y', P.ResizeFactorY);
  Result.Add('effective_pixel_size_x_um', P.EffectivePixelSizeXUM);
  Result.Add('effective_pixel_size_y_um', P.EffectivePixelSizeYUM);
  Result.Add('requested_width_px', P.RequestedWidthPX);
  Result.Add('requested_height_px', P.RequestedHeightPX);
  Result.Add('camera_fps', P.CameraFPS);
  Result.Add('resolution_source', P.ResolutionSource);
  Result.Add('active', P.Active);
  Result.Add('calibrated_at', FormatDateTime('yyyy-mm-dd hh:nn:ss', P.CalibratedAt));
end;

function JSONToProfile(AObj: TJSONObject): TOpticalProfile;
var
  FS: TFormatSettings;
  CamW, CamH: Integer;

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

  CamW := GetI('camera_width', 1920);
  CamH := GetI('camera_height', 1080);

  Result.ID := GetI('id', 0);
  Result.Name := GetS('name', 'Perfil Padrão');
  Result.CameraName := GetS('camera_name', 'Microscópio USB (Padrão Provisório)');
  Result.CameraWidth := CamW;
  Result.CameraHeight := CamH;
  Result.ObjectiveMagnification := GetF('objective_magnification', 40.0);
  Result.AdapterMagnification := GetF('adapter_magnification', 1.0);
  Result.SensorPixelSizeUM := GetF('sensor_pixel_size_um', 3.45);
  Result.TheoreticalPixelSizeUM := GetF('theoretical_pixel_size_um',
    CalculateTheoreticalScale(Result.ObjectiveMagnification, Result.AdapterMagnification, Result.SensorPixelSizeUM));

  // Compatibilidade com perfis antigos sem novos campos de resolução e resize
  Result.AcquisitionWidthPX := GetI('acquisition_width_px', CamW);
  Result.AcquisitionHeightPX := GetI('acquisition_height_px', CamH);
  Result.AnalysisWidthPX := GetI('analysis_width_px', Result.AcquisitionWidthPX);
  Result.AnalysisHeightPX := GetI('analysis_height_px', Result.AcquisitionHeightPX);

  Result.ResizeFactorX := GetF('resize_factor_x',
    CalculateResizeFactor(Result.AcquisitionWidthPX, Result.AnalysisWidthPX));
  Result.ResizeFactorY := GetF('resize_factor_y',
    CalculateResizeFactor(Result.AcquisitionHeightPX, Result.AnalysisHeightPX));

  Result.EffectivePixelSizeXUM := GetF('effective_pixel_size_x_um',
    Result.TheoreticalPixelSizeUM * Result.ResizeFactorX);
  Result.EffectivePixelSizeYUM := GetF('effective_pixel_size_y_um',
    Result.TheoreticalPixelSizeUM * Result.ResizeFactorY);

  Result.RequestedWidthPX := GetI('requested_width_px', Result.AcquisitionWidthPX);
  Result.RequestedHeightPX := GetI('requested_height_px', Result.AcquisitionHeightPX);
  Result.CameraFPS := GetF('camera_fps', 30.0);
  Result.ResolutionSource := GetS('resolution_source', 'DEVICE_REPORTED');

  Result.CalibratedPixelSizeUM := GetF('calibrated_pixel_size_um', Result.EffectivePixelSizeXUM);
  Result.CalibrationMethod := GetS('calibration_method', 'THEORETICAL');
  Result.CalibrationReferenceUM := GetF('calibration_reference_um', 0.0);
  Result.CalibrationReferencePX := GetF('calibration_reference_px', 0.0);
  Result.Active := True;
  Result.CalibratedAt := Now;
end;

end.
