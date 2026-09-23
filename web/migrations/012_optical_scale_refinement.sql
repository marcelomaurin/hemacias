-- Migração 012: Refinamento de calibração óptica, resoluções de aquisição/análise, escala anisotrópica e geometria celular

-- 1. Campos de resolução e escala anisotrópica em perfis ópticos
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS acquisition_width_px INT NULL AFTER camera_height;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS acquisition_height_px INT NULL AFTER acquisition_width_px;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS analysis_width_px INT NULL AFTER acquisition_height_px;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS analysis_height_px INT NULL AFTER analysis_width_px;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS resize_factor_x DECIMAL(8,4) NULL DEFAULT 1.0000 AFTER analysis_height_px;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS resize_factor_y DECIMAL(8,4) NULL DEFAULT 1.0000 AFTER resize_factor_x;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS effective_pixel_size_x_um DECIMAL(8,6) NULL AFTER theoretical_pixel_size_um;
ALTER TABLE optical_profiles ADD COLUMN IF NOT EXISTS effective_pixel_size_y_um DECIMAL(8,6) NULL AFTER effective_pixel_size_x_um;

-- 2. Circularidade bruta e fonte da geometria nas medições celulares
ALTER TABLE cell_measurements ADD COLUMN IF NOT EXISTS raw_circularity DECIMAL(6,4) NULL AFTER circularity;
ALTER TABLE cell_measurements ADD COLUMN IF NOT EXISTS geometry_source VARCHAR(30) NOT NULL DEFAULT 'POLYGON' AFTER measurement_reason;

-- 3. Snapshots detalhados de calibração e resolução na contagem
ALTER TABLE counts ADD COLUMN IF NOT EXISTS acquisition_width_snapshot INT NULL AFTER camera_height_snapshot;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS acquisition_height_snapshot INT NULL AFTER acquisition_width_snapshot;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS analysis_width_snapshot INT NULL AFTER acquisition_height_snapshot;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS analysis_height_snapshot INT NULL AFTER analysis_width_snapshot;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS effective_scale_x_um_px DECIMAL(8,6) NULL AFTER pixel_size_um_snapshot;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS effective_scale_y_um_px DECIMAL(8,6) NULL AFTER effective_scale_x_um_px;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS calibration_method_snapshot VARCHAR(50) NULL AFTER effective_scale_y_um_px;
