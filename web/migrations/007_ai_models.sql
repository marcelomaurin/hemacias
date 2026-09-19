USE hemacias;

CREATE TABLE IF NOT EXISTS ai_models (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL,
    name VARCHAR(160) NOT NULL,
    version VARCHAR(80) NOT NULL,
    model_type ENUM('YOLO_SEG','YOLO_DETECT','OUTRO') NOT NULL DEFAULT 'YOLO_SEG',
    status ENUM('TREINO','VALIDACAO','APROVADO','INATIVO') NOT NULL DEFAULT 'TREINO',
    file_path VARCHAR(500) NOT NULL,
    sha256 CHAR(64) NULL,
    dataset_ref VARCHAR(255) NULL,
    imgsz INT UNSIGNED NULL,
    epochs INT UNSIGNED NULL,
    classes_json JSON NULL,
    trained_at DATETIME NULL,
    notes TEXT NULL,
    created_by BIGINT UNSIGNED NULL,
    approved_by BIGINT UNSIGNED NULL,
    approved_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_ai_models_created_by FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_ai_models_approved_by FOREIGN KEY(approved_by) REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE KEY uq_ai_model_code_version(code,version),
    KEY idx_ai_model_status(status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ai_model_metrics (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    model_id BIGINT UNSIGNED NOT NULL,
    item_type_id BIGINT UNSIGNED NULL,
    metric_scope ENUM('GERAL','CLASSE') NOT NULL DEFAULT 'CLASSE',
    precision_value DECIMAL(10,6) NULL,
    recall_value DECIMAL(10,6) NULL,
    f1_value DECIMAL(10,6) NULL,
    map50_value DECIMAL(10,6) NULL,
    map5095_value DECIMAL(10,6) NULL,
    mae_value DECIMAL(14,6) NULL,
    bias_value DECIMAL(14,6) NULL,
    mape_value DECIMAL(14,6) NULL,
    sample_count INT UNSIGNED NULL,
    notes VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_ai_metrics_model FOREIGN KEY(model_id) REFERENCES ai_models(id) ON DELETE CASCADE,
    CONSTRAINT fk_ai_metrics_item FOREIGN KEY(item_type_id) REFERENCES count_item_types(id) ON DELETE SET NULL,
    UNIQUE KEY uq_ai_metric_scope(model_id,item_type_id,metric_scope)
) ENGINE=InnoDB;

ALTER TABLE count_protocols ADD COLUMN default_model_id BIGINT UNSIGNED NULL AFTER require_quality;
ALTER TABLE count_protocols
    ADD CONSTRAINT fk_protocol_default_model FOREIGN KEY(default_model_id) REFERENCES ai_models(id) ON DELETE SET NULL;

ALTER TABLE counts ADD COLUMN model_id BIGINT UNSIGNED NULL AFTER algorithm_version;
ALTER TABLE counts ADD COLUMN model_version_snapshot VARCHAR(80) NULL AFTER model_id;
ALTER TABLE counts ADD COLUMN model_sha256_snapshot CHAR(64) NULL AFTER model_version_snapshot;
ALTER TABLE counts
    ADD CONSTRAINT fk_counts_model FOREIGN KEY(model_id) REFERENCES ai_models(id) ON DELETE SET NULL;
