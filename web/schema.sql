CREATE DATABASE IF NOT EXISTS hemacias
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE hemacias;

CREATE TABLE IF NOT EXISTS users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    email VARCHAR(190) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('ADMIN','OPERADOR','LEITURA') NOT NULL DEFAULT 'OPERADOR',
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS patients (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    external_id VARCHAR(80) NULL,
    name VARCHAR(180) NOT NULL,
    birth_date DATE NULL,
    sex VARCHAR(30) NULL,
    document VARCHAR(80) NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_patient_external_id (external_id),
    KEY idx_patient_name (name)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS samples (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT UNSIGNED NOT NULL,
    sample_code VARCHAR(100) NOT NULL,
    collected_at DATETIME NULL,
    sample_type VARCHAR(100) NULL DEFAULT 'sangue',
    status ENUM('ABERTA','PROCESSADA','REVISADA','CANCELADA') NOT NULL DEFAULT 'ABERTA',
    notes TEXT NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_samples_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
    CONSTRAINT fk_samples_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE KEY uq_patient_sample (patient_id, sample_code),
    KEY idx_sample_code (sample_code)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS counts (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sample_id BIGINT UNSIGNED NOT NULL,
    method VARCHAR(80) NOT NULL DEFAULT 'opencv-hough',
    algorithm_version VARCHAR(80) NULL,
    scale_label VARCHAR(80) NULL,
    magnification DECIMAL(10,3) NULL,
    pixel_size_um DECIMAL(12,6) NULL,
    focus_score DECIMAL(12,3) NULL,
    image_quality VARCHAR(40) NULL,
    total_cells INT UNSIGNED NULL,
    notes TEXT NULL,
    source ENUM('WEB','PYTHON','IMPORT') NOT NULL DEFAULT 'WEB',
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_counts_sample FOREIGN KEY (sample_id) REFERENCES samples(id),
    CONSTRAINT fk_counts_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    KEY idx_counts_sample (sample_id),
    KEY idx_counts_created (created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS count_components (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    count_id BIGINT UNSIGNED NOT NULL,
    component_code VARCHAR(60) NOT NULL,
    component_name VARCHAR(120) NOT NULL,
    quantity INT UNSIGNED NOT NULL DEFAULT 0,
    unit VARCHAR(40) NOT NULL DEFAULT 'células/campo',
    confidence DECIMAL(7,4) NULL,
    metadata_json JSON NULL,
    CONSTRAINT fk_components_count FOREIGN KEY (count_id) REFERENCES counts(id) ON DELETE CASCADE,
    KEY idx_component_count (count_id),
    KEY idx_component_code (component_code)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sample_images (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sample_id BIGINT UNSIGNED NOT NULL,
    count_id BIGINT UNSIGNED NULL,
    original_name VARCHAR(255) NOT NULL,
    stored_name VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT UNSIGNED NOT NULL,
    sha256 CHAR(64) NOT NULL,
    width_px INT UNSIGNED NULL,
    height_px INT UNSIGNED NULL,
    scale_label VARCHAR(80) NULL,
    magnification DECIMAL(10,3) NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_images_sample FOREIGN KEY (sample_id) REFERENCES samples(id),
    CONSTRAINT fk_images_count FOREIGN KEY (count_id) REFERENCES counts(id) ON DELETE SET NULL,
    KEY idx_images_sample (sample_id),
    KEY idx_images_count (count_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    event_type VARCHAR(80) NOT NULL,
    entity_type VARCHAR(80) NULL,
    entity_id BIGINT UNSIGNED NULL,
    details_json JSON NULL,
    ip_address VARCHAR(64) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    KEY idx_audit_created (created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS image_annotations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    image_id BIGINT UNSIGNED NOT NULL,
    class_code VARCHAR(60) NOT NULL,
    class_name VARCHAR(120) NOT NULL,
    polygon_json JSON NOT NULL,
    source ENUM('MANUAL','AUTO_IMPORT') NOT NULL DEFAULT 'MANUAL',
    review_status ENUM('PENDENTE','APROVADA','REJEITADA') NOT NULL DEFAULT 'APROVADA',
    notes VARCHAR(500) NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_annotations_image FOREIGN KEY (image_id) REFERENCES sample_images(id) ON DELETE CASCADE,
    CONSTRAINT fk_annotations_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    KEY idx_annotations_image (image_id),
    KEY idx_annotations_class (class_code),
    KEY idx_annotations_status (review_status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS annotation_revisions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    image_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NULL,
    action_type VARCHAR(40) NOT NULL,
    details_json JSON NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_annotation_revision_image FOREIGN KEY (image_id) REFERENCES sample_images(id) ON DELETE CASCADE,
    CONSTRAINT fk_annotation_revision_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    KEY idx_annotation_revision_image (image_id),
    KEY idx_annotation_revision_created (created_at)
) ENGINE=InnoDB;

