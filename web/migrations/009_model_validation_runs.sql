USE hemacias;

CREATE TABLE IF NOT EXISTS ai_model_validation_runs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    model_id BIGINT UNSIGNED NOT NULL,
    iou_threshold DECIMAL(6,4) NOT NULL DEFAULT 0.5000,
    reviewed_images INT UNSIGNED NOT NULL DEFAULT 0,
    total_gt INT UNSIGNED NOT NULL DEFAULT 0,
    total_predictions INT UNSIGNED NOT NULL DEFAULT 0,
    true_positives INT UNSIGNED NOT NULL DEFAULT 0,
    false_positives INT UNSIGNED NOT NULL DEFAULT 0,
    false_negatives INT UNSIGNED NOT NULL DEFAULT 0,
    precision_value DECIMAL(10,6) NULL,
    recall_value DECIMAL(10,6) NULL,
    f1_value DECIMAL(10,6) NULL,
    mae_value DECIMAL(14,6) NULL,
    bias_value DECIMAL(14,6) NULL,
    mape_value DECIMAL(14,6) NULL,
    class_metrics_json JSON NULL,
    config_json JSON NULL,
    notes VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_validation_run_model FOREIGN KEY(model_id) REFERENCES ai_models(id) ON DELETE CASCADE,
    KEY idx_validation_model_created(model_id,created_at)
) ENGINE=InnoDB;
