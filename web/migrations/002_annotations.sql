USE hemacias;

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
