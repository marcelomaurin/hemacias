unit measurement_types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Perfil Óptico }
  TOpticalProfile = record
    ID: Int64;
    Name: string;
    CameraName: string;
    CameraWidth: Integer;
    CameraHeight: Integer;
    ObjectiveMagnification: Double;
    AdapterMagnification: Double;
    SensorPixelSizeUM: Double;
    TheoreticalPixelSizeUM: Double; // Escala óptica teórica (sensor / (obj * adapter))
    CalibratedPixelSizeUM: Double;
    CalibrationMethod: string; // 'STAGE_MICROMETER', 'SCALE_BAR', 'MANUAL', 'THEORETICAL', 'ESTIMATED_REFERENCE'
    CalibrationReferenceUM: Double;
    CalibrationReferencePX: Double;
    AcquisitionWidthPX: Integer;
    AcquisitionHeightPX: Integer;
    AnalysisWidthPX: Integer;
    AnalysisHeightPX: Integer;
    EffectivePixelSizeXUM: Double;
    EffectivePixelSizeYUM: Double;
    ResizeFactorX: Double;
    ResizeFactorY: Double;
    Active: Boolean;
    CalibratedAt: TDateTime;
  end;
  TOpticalProfileArray = array of TOpticalProfile;

  { Medição Individual de Célula }
  TCellMeasurement = record
    ObjectID: Integer;
    ClassCode: string;
    Confidence: Double;
    CenterX: Double;
    CenterY: Double;
    AreaPX: Double;
    PerimeterPX: Double;
    EquivalentDiameterPX: Double;
    MajorAxisPX: Double;
    MinorAxisPX: Double;
    Circularity: Double;
    RawCircularity: Double;
    AspectRatio: Double;
    AreaUM2: Double;
    PerimeterUM: Double;
    EquivalentDiameterUM: Double;
    MajorAxisUM: Double;
    MinorAxisUM: Double;
    TouchesBorder: Boolean;
    MeasurementValid: Boolean;
    MeasurementReason: string;
    GeometrySource: string; // 'MASK', 'POLYGON', 'BOUNDING_BOX_ESTIMATE'
    Source: string; // 'AI', 'HUMAN_REVIEW', 'CALCULATED'
  end;
  TCellMeasurementArray = array of TCellMeasurement;

  { Estatísticas Populacionais da Morfometria }
  TMorphometryStatistics = record
    CellCount: Integer;
    ValidCellCount: Integer;
    ExcludedBorderCount: Integer;
    BoundingBoxOnlyCount: Integer;
    ValidSegmentationCount: Integer;
    MeanDiameterUM: Double;
    MedianDiameterUM: Double;
    StdDevDiameterUM: Double;
    MinDiameterUM: Double;
    MaxDiameterUM: Double;
    P10DiameterUM: Double;
    P25DiameterUM: Double;
    P75DiameterUM: Double;
    P90DiameterUM: Double;
    CVSizePercent: Double; // "CV do diâmetro microscópico"
    MeanAreaUM2: Double;
    MeanCircularity: Double;
    MeanMajorAxisUM: Double;
    MeanMinorAxisUM: Double;
    MeanAspectRatio: Double;
  end;

  { Dados Laboratoriais Externos e Índices Clínicos }
  THematologyLabData = record
    HasData: Boolean;
    RBC: Double;        // milhões / uL (x 10^6 / uL)
    Hemoglobin: Double; // g/dL
    Hematocrit: Double; // %
    MCV: Double;        // VCM laboratorial = (Hct * 10) / RBC (fL)
    MCH: Double;        // HCM laboratorial = (Hb * 10) / RBC (pg)
    MCHC: Double;       // CHCM laboratorial = (Hb * 100) / Hct (g/dL)
  end;

implementation

end.
