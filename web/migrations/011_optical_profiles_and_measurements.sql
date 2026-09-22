-- Migração 011: Perfis ópticos, medições individuais de células e dados laboratoriais externos

CREATE TABLE IF NOT EXISTS optical_profiles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    camera_name VARCHAR(100) NULL,
    camera_width INT NULL,
    camera_height INT NULL,
    objective_magnification DECIMAL(8,2) NOT NULL DEFAULT 40.0,
    adapter_magnification DECIMAL(8,2) NOT NULL DEFAULT 1.0,
    sensor_pixel_size_um DECIMAL(8,4) NOT NULL DEFAULT 3.4500,
    theoretical_pixel_size_um DECIMAL(8,6) NOT NULL,
    calibrated_pixel_size_um DECIMAL(8,6) NOT NULL,
    calibration_method VARCHAR(50) NOT NULL DEFAULT 'THEORETICAL',
    calibration_reference_um DECIMAL(8,2) NULL,
    calibration_reference_px DECIMAL(8,2) NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cell_measurements (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    count_id INT NOT NULL,
    image_id INT NOT NULL,
    annotation_id INT NULL,
    component_code VARCHAR(50) NOT NULL,
    object_index INT NOT NULL,
    confidence DECIMAL(5,4) NOT NULL,
    center_x_px DECIMAL(8,2) NOT NULL,
    center_y_px DECIMAL(8,2) NOT NULL,
    area_px2 DECIMAL(12,2) NOT NULL,
    perimeter_px DECIMAL(10,2) NOT NULL,
    diameter_px DECIMAL(10,2) NOT NULL,
    major_axis_px DECIMAL(10,2) NULL,
    minor_axis_px DECIMAL(10,2) NULL,
    area_um2 DECIMAL(10,4) NOT NULL,
    perimeter_um DECIMAL(10,4) NOT NULL,
    diameter_um DECIMAL(8,4) NOT NULL,
    major_axis_um DECIMAL(8,4) NULL,
    minor_axis_um DECIMAL(8,4) NULL,
    circularity DECIMAL(6,4) NOT NULL,
    aspect_ratio DECIMAL(6,4) NULL,
    touches_border TINYINT(1) NOT NULL DEFAULT 0,
    measurement_valid TINYINT(1) NOT NULL DEFAULT 1,
    measurement_reason VARCHAR(255) NULL,
    source VARCHAR(30) NOT NULL DEFAULT 'AI',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cm_count (count_id),
    INDEX idx_cm_image (image_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sample_hematology (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sample_id INT NOT NULL,
    rbc DECIMAL(6,2) NULL,
    hemoglobin DECIMAL(5,2) NULL,
    hematocrit DECIMAL(5,2) NULL,
    mcv DECIMAL(6,2) NULL,
    mch DECIMAL(6,2) NULL,
    mchc DECIMAL(6,2) NULL,
    source VARCHAR(30) NOT NULL DEFAULT 'MANUAL',
    measured_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sh_sample (sample_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE counts ADD COLUMN IF NOT EXISTS optical_profile_id INT NULL;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS objective_magnification DECIMAL(8,2) NULL;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS adapter_magnification DECIMAL(8,2) NULL;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS pixel_size_um_snapshot DECIMAL(8,6) NULL;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS camera_name_snapshot VARCHAR(100) NULL;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS camera_width_snapshot INT NULL;
ALTER TABLE counts ADD COLUMN IF NOT EXISTS camera_height_snapshot INT NULL;
