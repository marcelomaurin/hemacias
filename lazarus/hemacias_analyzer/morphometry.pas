unit morphometry;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, measurement_types;

type
  TPointD = record
    X, Y: Double;
  end;
  TPointDArray = array of TPointD;

function ParsePolygonString(const S: string; AX1, AY1, AX2, AY2: Integer): TPointDArray;
function CalculatePolygonAreaPX(const Pts: TPointDArray; AFallbackW, AFallbackH: Double): Double;
function CalculatePolygonPerimeterPX(const Pts: TPointDArray; AFallbackW, AFallbackH: Double): Double;
function CalculatePolygonPerimeterUM(const Pts: TPointDArray;
  APixelSizeXUM, APixelSizeYUM, AFallbackW, AFallbackH: Double): Double;

procedure CalculatePolygonPCAAxes(const Pts: TPointDArray;
  AFallbackW, AFallbackH: Double;
  APixelSizeXUM, APixelSizeYUM: Double;
  out AMajorPX, AMinorPX, AMajorUM, AMinorUM, AAspect: Double;
  out AIsPolygon: Boolean);

procedure CalculatePolygonAxes(const Pts: TPointDArray; AAreaPX, AFallbackW, AFallbackH: Double;
  out AMajorPX, AMinorPX, AAspect: Double);

function CheckTouchesBorder(const Pts: TPointDArray; AX1, AY1, AX2, AY2: Integer;
  AImgW, AImgH: Integer): Boolean;

function MeasureObject(AObjectID: Integer; const AClassCode: string; AConfidence: Double;
  AX1, AY1, AX2, AY2: Integer; const APolygonStr: string;
  APixelSizeXUM, APixelSizeYUM: Double; AImgW, AImgH: Integer;
  AAllowBorder: Boolean; AMinAreaPX, AMaxAreaPX, AMinCircularity: Double;
  const ASource: string): TCellMeasurement; overload;

function MeasureObject(AObjectID: Integer; const AClassCode: string; AConfidence: Double;
  AX1, AY1, AX2, AY2: Integer; const APolygonStr: string;
  APixelSizeUM: Double; AImgW, AImgH: Integer;
  AAllowBorder: Boolean; AMinAreaPX, AMaxAreaPX, AMinCircularity: Double;
  const ASource: string): TCellMeasurement; overload;

function ComputeMorphometryStatistics(const AMeasurements: TCellMeasurementArray): TMorphometryStatistics;

function CalculateLabIndices(ARBC, AHemoglobin, AHematocrit: Double): THematologyLabData;

implementation

function ParsePolygonString(const S: string; AX1, AY1, AX2, AY2: Integer): TPointDArray;
var
  Tokens, XY: TStringList;
  I: Integer;
  X, Y: Double;
  FS: TFormatSettings;
begin
  SetLength(Result, 0);
  if Trim(S) = '' then Exit;

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  Tokens := TStringList.Create;
  XY := TStringList.Create;
  try
    ExtractStrings(['|'], [], PChar(S), Tokens);
    SetLength(Result, Tokens.Count);
    for I := 0 to Tokens.Count - 1 do
    begin
      XY.Clear;
      ExtractStrings([':'], [], PChar(Tokens[I]), XY);
      if XY.Count >= 2 then
      begin
        X := StrToFloatDef(StringReplace(XY[0], ',', '.', [rfReplaceAll]), AX1, FS);
        Y := StrToFloatDef(StringReplace(XY[1], ',', '.', [rfReplaceAll]), AY1, FS);
        Result[I].X := X;
        Result[I].Y := Y;
      end
      else
      begin
        Result[I].X := AX1;
        Result[I].Y := AY1;
      end;
    end;
  finally
    XY.Free;
    Tokens.Free;
  end;
end;

function CalculatePolygonAreaPX(const Pts: TPointDArray; AFallbackW, AFallbackH: Double): Double;
var
  I, N: Integer;
  Sum: Double;
begin
  N := Length(Pts);
  if N >= 3 then
  begin
    // Fórmula do Cadarço (Shoelace Formula / Teorema de Green)
    Sum := 0.0;
    for I := 0 to N - 1 do
    begin
      if I = N - 1 then
        Sum := Sum + (Pts[I].X * Pts[0].Y - Pts[0].X * Pts[I].Y)
      else
        Sum := Sum + (Pts[I].X * Pts[I + 1].Y - Pts[I + 1].X * Pts[I].Y);
    end;
    Result := Abs(Sum) * 0.5;
    if Result > 0.1 then Exit;
  end;

  // Fallback: área da elipse circunscrita na bounding box
  Result := (Pi / 4.0) * Max(1.0, AFallbackW) * Max(1.0, AFallbackH);
end;

function CalculatePolygonPerimeterPX(const Pts: TPointDArray; AFallbackW, AFallbackH: Double): Double;
var
  I, N: Integer;
  P, A, B: Double;
begin
  N := Length(Pts);
  if N >= 3 then
  begin
    P := 0.0;
    for I := 0 to N - 1 do
    begin
      if I = N - 1 then
        P := P + Sqrt(Sqr(Pts[0].X - Pts[I].X) + Sqr(Pts[0].Y - Pts[I].Y))
      else
        P := P + Sqrt(Sqr(Pts[I + 1].X - Pts[I].X) + Sqr(Pts[I + 1].Y - Pts[I].Y));
    end;
    if P > 1.0 then Exit(P);
  end;

  // Fallback: aproximação de Ramanujan para perímetro de elipse
  A := Max(0.5, AFallbackW / 2.0);
  B := Max(0.5, AFallbackH / 2.0);
  Result := Pi * (3.0 * (A + B) - Sqrt((3.0 * A + B) * (A + 3.0 * B)));
end;

function CalculatePolygonPerimeterUM(const Pts: TPointDArray;
  APixelSizeXUM, APixelSizeYUM, AFallbackW, AFallbackH: Double): Double;
var
  I, N: Integer;
  P, DX, DY, A_UM, B_UM: Double;
begin
  N := Length(Pts);
  if N >= 3 then
  begin
    P := 0.0;
    for I := 0 to N - 1 do
    begin
      if I = N - 1 then
      begin
        DX := (Pts[0].X - Pts[I].X) * APixelSizeXUM;
        DY := (Pts[0].Y - Pts[I].Y) * APixelSizeYUM;
      end
      else
      begin
        DX := (Pts[I + 1].X - Pts[I].X) * APixelSizeXUM;
        DY := (Pts[I + 1].Y - Pts[I].Y) * APixelSizeYUM;
      end;
      P := P + Sqrt(Sqr(DX) + Sqr(DY));
    end;
    if P > 0.0001 then Exit(P);
  end;

  // Fallback físico de elipse com anisotropia
  A_UM := Max(0.5, (AFallbackW / 2.0)) * APixelSizeXUM;
  B_UM := Max(0.5, (AFallbackH / 2.0)) * APixelSizeYUM;
  Result := Pi * (3.0 * (A_UM + B_UM) - Sqrt((3.0 * A_UM + B_UM) * (A_UM + 3.0 * B_UM)));
end;

procedure CalculatePolygonPCAAxes(const Pts: TPointDArray;
  AFallbackW, AFallbackH: Double;
  APixelSizeXUM, APixelSizeYUM: Double;
  out AMajorPX, AMinorPX, AMajorUM, AMinorUM, AAspect: Double;
  out AIsPolygon: Boolean);
var
  I, N: Integer;
  MeanX, MeanY, DiffX, DiffY: Double;
  VarX, VarY, CovXY: Double;
  Theta, CosT, SinT, Proj1, Proj2: Double;
  MinP1, MaxP1, MinP2, MaxP2: Double;
  // Variáveis em µm
  MeanXUM, MeanYUM, DiffXUM, DiffYUM: Double;
  VarXUM, VarYUM, CovXYUM: Double;
  ThetaUM, CosTUM, SinTUM, Proj1UM, Proj2UM: Double;
  MinP1UM, MaxP1UM, MinP2UM, MaxP2UM: Double;
  Tmp: Double;
begin
  N := Length(Pts);
  if N >= 3 then
  begin
    // 1. Centroide em pixels
    MeanX := 0.0; MeanY := 0.0;
    for I := 0 to N - 1 do
    begin
      MeanX := MeanX + Pts[I].X;
      MeanY := MeanY + Pts[I].Y;
    end;
    MeanX := MeanX / N;
    MeanY := MeanY / N;

    // 2. Matriz de covariância em pixels
    VarX := 0.0; VarY := 0.0; CovXY := 0.0;
    for I := 0 to N - 1 do
    begin
      DiffX := Pts[I].X - MeanX;
      DiffY := Pts[I].Y - MeanY;
      VarX := VarX + Sqr(DiffX);
      VarY := VarY + Sqr(DiffY);
      CovXY := CovXY + (DiffX * DiffY);
    end;
    VarX := VarX / N;
    VarY := VarY / N;
    CovXY := CovXY / N;

    if (VarX + VarY) > 0.0001 then
    begin
      // Direção principal dos autovetores via matriz 2x2
      Theta := 0.5 * ArcTan2(2.0 * CovXY, VarX - VarY);
      CosT := Cos(Theta);
      SinT := Sin(Theta);

      MinP1 := 1e12; MaxP1 := -1e12;
      MinP2 := 1e12; MaxP2 := -1e12;
      for I := 0 to N - 1 do
      begin
        Proj1 := Pts[I].X * CosT + Pts[I].Y * SinT;
        Proj2 := -Pts[I].X * SinT + Pts[I].Y * CosT;
        if Proj1 < MinP1 then MinP1 := Proj1;
        if Proj1 > MaxP1 then MaxP1 := Proj1;
        if Proj2 < MinP2 then MinP2 := Proj2;
        if Proj2 > MaxP2 then MaxP2 := Proj2;
      end;

      AMajorPX := Max(0.1, MaxP1 - MinP1);
      AMinorPX := Max(0.1, MaxP2 - MinP2);
      if AMinorPX > AMajorPX then
      begin
        Tmp := AMajorPX; AMajorPX := AMinorPX; AMinorPX := Tmp;
      end;

      // 3. Eixos físicos em µm via PCA com calibração anisotrópica
      MeanXUM := 0.0; MeanYUM := 0.0;
      for I := 0 to N - 1 do
      begin
        MeanXUM := MeanXUM + (Pts[I].X * APixelSizeXUM);
        MeanYUM := MeanYUM + (Pts[I].Y * APixelSizeYUM);
      end;
      MeanXUM := MeanXUM / N;
      MeanYUM := MeanYUM / N;

      VarXUM := 0.0; VarYUM := 0.0; CovXYUM := 0.0;
      for I := 0 to N - 1 do
      begin
        DiffXUM := (Pts[I].X * APixelSizeXUM) - MeanXUM;
        DiffYUM := (Pts[I].Y * APixelSizeYUM) - MeanYUM;
        VarXUM := VarXUM + Sqr(DiffXUM);
        VarYUM := VarYUM + Sqr(DiffYUM);
        CovXYUM := CovXYUM + (DiffXUM * DiffYUM);
      end;
      VarXUM := VarXUM / N;
      VarYUM := VarYUM / N;
      CovXYUM := CovXYUM / N;

      ThetaUM := 0.5 * ArcTan2(2.0 * CovXYUM, VarXUM - VarYUM);
      CosTUM := Cos(ThetaUM);
      SinTUM := Sin(ThetaUM);

      MinP1UM := 1e12; MaxP1UM := -1e12;
      MinP2UM := 1e12; MaxP2UM := -1e12;
      for I := 0 to N - 1 do
      begin
        Proj1UM := (Pts[I].X * APixelSizeXUM) * CosTUM + (Pts[I].Y * APixelSizeYUM) * SinTUM;
        Proj2UM := -(Pts[I].X * APixelSizeXUM) * SinTUM + (Pts[I].Y * APixelSizeYUM) * CosTUM;
        if Proj1UM < MinP1UM then MinP1UM := Proj1UM;
        if Proj1UM > MaxP1UM then MaxP1UM := Proj1UM;
        if Proj2UM < MinP2UM then MinP2UM := Proj2UM;
        if Proj2UM > MaxP2UM then MaxP2UM := Proj2UM;
      end;

      AMajorUM := Max(0.0001, MaxP1UM - MinP1UM);
      AMinorUM := Max(0.0001, MaxP2UM - MinP2UM);
      if AMinorUM > AMajorUM then
      begin
        Tmp := AMajorUM; AMajorUM := AMinorUM; AMinorUM := Tmp;
      end;

      AAspect := AMajorPX / Max(0.001, AMinorPX);
      AIsPolygon := True;
      Exit;
    end;
  end;

  // Fallback: estimativa por bounding box (não é polígono válido)
  AIsPolygon := False;
  if AFallbackW >= AFallbackH then
  begin
    AMajorPX := Max(1.0, AFallbackW);
    AMinorPX := Max(1.0, AFallbackH);
  end
  else
  begin
    AMajorPX := Max(1.0, AFallbackH);
    AMinorPX := Max(1.0, AFallbackW);
  end;

  AMajorUM := AMajorPX * APixelSizeXUM;
  AMinorUM := AMinorPX * APixelSizeYUM;
  if AMinorUM > AMajorUM then
  begin
    Tmp := AMajorUM; AMajorUM := AMinorUM; AMinorUM := Tmp;
  end;
  AAspect := AMajorPX / Max(0.001, AMinorPX);
end;

procedure CalculatePolygonAxes(const Pts: TPointDArray; AAreaPX, AFallbackW, AFallbackH: Double;
  out AMajorPX, AMinorPX, AAspect: Double);
var
  MajUM, MinUM: Double;
  IsPoly: Boolean;
begin
  CalculatePolygonPCAAxes(Pts, AFallbackW, AFallbackH, 1.0, 1.0,
    AMajorPX, AMinorPX, MajUM, MinUM, AAspect, IsPoly);
end;

function CheckTouchesBorder(const Pts: TPointDArray; AX1, AY1, AX2, AY2: Integer;
  AImgW, AImgH: Integer): Boolean;
var
  I: Integer;
  Margin: Integer;
begin
  Result := False;
  Margin := 2; // tolerância de 2 pixels da margem
  if (AImgW <= 0) or (AImgH <= 0) then Exit;

  if (AX1 <= Margin) or (AY1 <= Margin) or (AX2 >= AImgW - Margin) or (AY2 >= AImgH - Margin) then
    Exit(True);

  for I := 0 to High(Pts) do
  begin
    if (Pts[I].X <= Margin) or (Pts[I].Y <= Margin) or
       (Pts[I].X >= AImgW - Margin) or (Pts[I].Y >= AImgH - Margin) then
      Exit(True);
  end;
end;

function MeasureObject(AObjectID: Integer; const AClassCode: string; AConfidence: Double;
  AX1, AY1, AX2, AY2: Integer; const APolygonStr: string;
  APixelSizeXUM, APixelSizeYUM: Double; AImgW, AImgH: Integer;
  AAllowBorder: Boolean; AMinAreaPX, AMaxAreaPX, AMinCircularity: Double;
  const ASource: string): TCellMeasurement;
var
  Pts: TPointDArray;
  W, H: Double;
  ScaleX, ScaleY: Double;
  IsPolygon: Boolean;
  RawCirc: Double;
begin
  ScaleX := Max(0.00001, APixelSizeXUM);
  ScaleY := Max(0.00001, APixelSizeYUM);

  Pts := ParsePolygonString(APolygonStr, AX1, AY1, AX2, AY2);

  W := Max(1.0, Abs(AX2 - AX1));
  H := Max(1.0, Abs(AY2 - AY1));

  Result.ObjectID := AObjectID;
  Result.ClassCode := AClassCode;
  Result.Confidence := AConfidence;
  Result.CenterX := (AX1 + AX2) / 2.0;
  Result.CenterY := (AY1 + AY2) / 2.0;
  Result.Source := ASource;

  // Medidas em pixels
  Result.AreaPX := CalculatePolygonAreaPX(Pts, W, H);
  Result.PerimeterPX := CalculatePolygonPerimeterPX(Pts, W, H);
  Result.EquivalentDiameterPX := 2.0 * Sqrt(Max(0.0, Result.AreaPX / Pi));

  // Cálculo de eixos via PCA (invariante à rotação)
  CalculatePolygonPCAAxes(Pts, W, H, ScaleX, ScaleY,
    Result.MajorAxisPX, Result.MinorAxisPX,
    Result.MajorAxisUM, Result.MinorAxisUM,
    Result.AspectRatio, IsPolygon);

  if IsPolygon then
    Result.GeometrySource := 'POLYGON'
  else
    Result.GeometrySource := 'BOUNDING_BOX_ESTIMATE';

  // Circularidade: 4*pi*A / P^2
  if Result.PerimeterPX > 0.0 then
    RawCirc := (4.0 * Pi * Result.AreaPX) / Sqr(Result.PerimeterPX)
  else
    RawCirc := 0.0;

  Result.RawCircularity := RawCirc;
  Result.Circularity := Min(1.0, Max(0.0, RawCirc));

  // Conversões físicas para micrômetros com suporte a anisotropia
  Result.AreaUM2 := Result.AreaPX * ScaleX * ScaleY;
  Result.PerimeterUM := CalculatePolygonPerimeterUM(Pts, ScaleX, ScaleY, W, H);
  Result.EquivalentDiameterUM := 2.0 * Sqrt(Max(0.0, Result.AreaUM2 / Pi));

  // Verificação de borda e critérios de validade
  Result.TouchesBorder := CheckTouchesBorder(Pts, AX1, AY1, AX2, AY2, AImgW, AImgH);
  Result.MeasurementValid := True;
  Result.MeasurementReason := '';

  // Objetos estimados apenas por bounding box são contáveis, mas excluídos da morfometria científica
  if Result.GeometrySource = 'BOUNDING_BOX_ESTIMATE' then
  begin
    Result.MeasurementValid := False;
    Result.MeasurementReason := 'Estimativa apenas por bounding box (sem polígono)';
  end
  else if Result.TouchesBorder and (not AAllowBorder) then
  begin
    Result.MeasurementValid := False;
    Result.MeasurementReason := 'Objeto cortado na borda da imagem';
  end
  else if (AMinAreaPX > 0) and (Result.AreaPX < AMinAreaPX) then
  begin
    Result.MeasurementValid := False;
    Result.MeasurementReason := 'Área abaixo do limiar mínimo';
  end
  else if (AMaxAreaPX > 0) and (Result.AreaPX > AMaxAreaPX) then
  begin
    Result.MeasurementValid := False;
    Result.MeasurementReason := 'Área acima do limiar máximo';
  end
  else if (AMinCircularity > 0) and (Result.Circularity < AMinCircularity) then
  begin
    Result.MeasurementValid := False;
    Result.MeasurementReason := 'Circularidade abaixo do limiar mínimo';
  end
  else if (Result.RawCircularity > 1.05) then
  begin
    Result.MeasurementReason := 'Aviso: circularidade bruta superior a 1.05 (artefato de contorno)';
  end
  else if (Result.RawCircularity < 0.0) then
  begin
    Result.MeasurementValid := False;
    Result.MeasurementReason := 'Erro: circularidade bruta negativa';
  end;
end;

function MeasureObject(AObjectID: Integer; const AClassCode: string; AConfidence: Double;
  AX1, AY1, AX2, AY2: Integer; const APolygonStr: string;
  APixelSizeUM: Double; AImgW, AImgH: Integer;
  AAllowBorder: Boolean; AMinAreaPX, AMaxAreaPX, AMinCircularity: Double;
  const ASource: string): TCellMeasurement;
begin
  Result := MeasureObject(AObjectID, AClassCode, AConfidence,
    AX1, AY1, AX2, AY2, APolygonStr,
    APixelSizeUM, APixelSizeUM, AImgW, AImgH,
    AAllowBorder, AMinAreaPX, AMaxAreaPX, AMinCircularity,
    ASource);
end;

function QuickSelectVal(var Arr: array of Double; L, R, K: Integer): Double;
var
  Pivot, Tmp: Double;
  I, J: Integer;
begin
  while L < R do
  begin
    Pivot := Arr[R];
    I := L;
    for J := L to R - 1 do
    begin
      if Arr[J] <= Pivot then
      begin
        Tmp := Arr[I]; Arr[I] := Arr[J]; Arr[J] := Tmp;
        Inc(I);
      end;
    end;
    Tmp := Arr[I]; Arr[I] := Arr[R]; Arr[R] := Tmp;
    if I = K then Exit(Arr[I])
    else if I < K then L := I + 1
    else R := I - 1;
  end;
  Result := Arr[L];
end;

function PercentileOfArray(const AValues: array of Double; APercentile: Double): Double;
var
  CopyArr: array of Double;
  N, K: Integer;
  I: Integer;
begin
  N := Length(AValues);
  if N = 0 then Exit(0.0);
  if N = 1 then Exit(AValues[0]);

  SetLength(CopyArr, N);
  for I := 0 to N - 1 do CopyArr[I] := AValues[I];

  K := Round((APercentile / 100.0) * (N - 1));
  K := Max(0, Min(N - 1, K));
  Result := QuickSelectVal(CopyArr, 0, N - 1, K);
end;

function ComputeMorphometryStatistics(const AMeasurements: TCellMeasurementArray): TMorphometryStatistics;
var
  I, N: Integer;
  SumD, SumArea, SumCirc, SumMaj, SumMin, SumAspect: Double;
  SumSqDiff: Double;
  Diams: array of Double;
  D: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.CellCount := Length(AMeasurements);
  if Result.CellCount = 0 then Exit;

  Result.MinDiameterUM := 999999.0;
  Result.MaxDiameterUM := 0.0;
  SumD := 0; SumArea := 0; SumCirc := 0; SumMaj := 0; SumMin := 0; SumAspect := 0;
  N := 0;

  for I := 0 to High(AMeasurements) do
  begin
    if AMeasurements[I].TouchesBorder then
      Inc(Result.ExcludedBorderCount);

    if AMeasurements[I].GeometrySource = 'BOUNDING_BOX_ESTIMATE' then
      Inc(Result.BoundingBoxOnlyCount)
    else if (AMeasurements[I].GeometrySource = 'POLYGON') or (AMeasurements[I].GeometrySource = 'MASK') then
      Inc(Result.ValidSegmentationCount);

    if AMeasurements[I].MeasurementValid then
    begin
      Inc(N);
      D := AMeasurements[I].EquivalentDiameterUM;
      SumD := SumD + D;
      SumArea := SumArea + AMeasurements[I].AreaUM2;
      SumCirc := SumCirc + AMeasurements[I].Circularity;
      SumMaj := SumMaj + AMeasurements[I].MajorAxisUM;
      SumMin := SumMin + AMeasurements[I].MinorAxisUM;
      SumAspect := SumAspect + AMeasurements[I].AspectRatio;

      if D < Result.MinDiameterUM then Result.MinDiameterUM := D;
      if D > Result.MaxDiameterUM then Result.MaxDiameterUM := D;
    end;
  end;

  Result.ValidCellCount := N;
  if N > 0 then
  begin
    Result.MeanDiameterUM := SumD / N;
    Result.MeanAreaUM2 := SumArea / N;
    Result.MeanCircularity := SumCirc / N;
    Result.MeanMajorAxisUM := SumMaj / N;
    Result.MeanMinorAxisUM := SumMin / N;
    Result.MeanAspectRatio := SumAspect / N;

    // Desvio Padrão e CV do diâmetro microscópico
    SumSqDiff := 0.0;
    SetLength(Diams, N);
    N := 0;
    for I := 0 to High(AMeasurements) do
    begin
      if AMeasurements[I].MeasurementValid then
      begin
        Diams[N] := AMeasurements[I].EquivalentDiameterUM;
        SumSqDiff := SumSqDiff + Sqr(Diams[N] - Result.MeanDiameterUM);
        Inc(N);
      end;
    end;

    if N > 1 then
      Result.StdDevDiameterUM := Sqrt(SumSqDiff / (N - 1))
    else
      Result.StdDevDiameterUM := 0.0;

    if Result.MeanDiameterUM > 0.0 then
      Result.CVSizePercent := (Result.StdDevDiameterUM / Result.MeanDiameterUM) * 100.0
    else
      Result.CVSizePercent := 0.0;

    // Percentis
    Result.P10DiameterUM := PercentileOfArray(Diams, 10.0);
    Result.P25DiameterUM := PercentileOfArray(Diams, 25.0);
    Result.MedianDiameterUM := PercentileOfArray(Diams, 50.0);
    Result.P75DiameterUM := PercentileOfArray(Diams, 75.0);
    Result.P90DiameterUM := PercentileOfArray(Diams, 90.0);
  end
  else
  begin
    Result.MinDiameterUM := 0.0;
  end;
end;

function CalculateLabIndices(ARBC, AHemoglobin, AHematocrit: Double): THematologyLabData;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RBC := ARBC;
  Result.Hemoglobin := AHemoglobin;
  Result.Hematocrit := AHematocrit;

  if (ARBC > 0.1) and (AHematocrit > 1.0) and (AHemoglobin > 0.5) then
  begin
    Result.HasData := True;
    // MCV (fL) = (Hematócrito % * 10) / RBC
    Result.MCV := (AHematocrit * 10.0) / ARBC;
    // MCH (pg) = (Hemoglobina g/dL * 10) / RBC
    Result.MCH := (AHemoglobin * 10.0) / ARBC;
    // MCHC (g/dL) = (Hemoglobina g/dL * 100) / Hematócrito %
    Result.MCHC := (AHemoglobin * 100.0) / AHematocrit;
  end
  else
  begin
    Result.HasData := False;
  end;
end;

end.
