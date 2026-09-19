USE hemacias;

CREATE TABLE IF NOT EXISTS dataset_split_runs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    group_mode ENUM('SAMPLE','PATIENT') NOT NULL,
    train_ratio DECIMAL(6,4) NOT NULL,
    val_ratio DECIMAL(6,4) NOT NULL,
    test_ratio DECIMAL(6,4) NOT NULL,
    seed_value VARCHAR(120) NOT NULL,
    eligible_images INT UNSIGNED NOT NULL DEFAULT 0,
    group_count INT UNSIGNED NOT NULL DEFAULT 0,
    train_images INT UNSIGNED NOT NULL DEFAULT 0,
    val_images INT UNSIGNED NOT NULL DEFAULT 0,
    test_images INT UNSIGNED NOT NULL DEFAULT 0,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    details_json JSON NULL,
    CONSTRAINT fk_dataset_split_run_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    KEY idx_dataset_split_run_created (created_at)
) ENGINE=InnoDB;
