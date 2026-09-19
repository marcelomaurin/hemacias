USE hemacias;

CREATE TABLE IF NOT EXISTS dataset_items (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    image_id BIGINT UNSIGNED NOT NULL UNIQUE,
    review_state ENUM('PENDENTE','REVISADA','APROVADA','REJEITADA') NOT NULL DEFAULT 'PENDENTE',
    split_set ENUM('NAO_DEFINIDO','TRAIN','VAL','TEST') NOT NULL DEFAULT 'NAO_DEFINIDO',
    included TINYINT(1) NOT NULL DEFAULT 1,
    notes VARCHAR(500) NULL,
    reviewed_by BIGINT UNSIGNED NULL,
    reviewed_at DATETIME NULL,
    approved_by BIGINT UNSIGNED NULL,
    approved_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_dataset_item_image FOREIGN KEY (image_id) REFERENCES sample_images(id) ON DELETE CASCADE,
    CONSTRAINT fk_dataset_item_reviewed_by FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_dataset_item_approved_by FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL,
    KEY idx_dataset_state (review_state),
    KEY idx_dataset_split (split_set),
    KEY idx_dataset_included (included)
) ENGINE=InnoDB;

INSERT INTO dataset_items(image_id, review_state)
SELECT i.id,
       CASE
         WHEN EXISTS(SELECT 1 FROM image_annotations a WHERE a.image_id=i.id AND a.source='MANUAL') THEN 'REVISADA'
         ELSE 'PENDENTE'
       END
FROM sample_images i
LEFT JOIN dataset_items d ON d.image_id=i.id
WHERE d.id IS NULL;
