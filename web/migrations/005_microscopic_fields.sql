USE hemacias;

CREATE TABLE IF NOT EXISTS microscopic_fields (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sample_id BIGINT UNSIGNED NOT NULL,
    field_no INT UNSIGNED NOT NULL,
    status ENUM('ACEITA','REJEITADA','REVISAR') NOT NULL DEFAULT 'REVISAR',
    quality_score DECIMAL(8,3) NULL,
    focus_score DECIMAL(12,3) NULL,
    quality_reason VARCHAR(255) NULL,
    included_in_summary TINYINT(1) NOT NULL DEFAULT 1,
    reviewed_by BIGINT UNSIGNED NULL,
    reviewed_at DATETIME NULL,
    notes VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_fields_sample FOREIGN KEY (sample_id) REFERENCES samples(id) ON DELETE CASCADE,
    CONSTRAINT fk_fields_reviewed_by FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE KEY uq_field_sample_no (sample_id, field_no),
    KEY idx_fields_sample_status (sample_id,status)
) ENGINE=InnoDB;

ALTER TABLE counts ADD COLUMN field_id BIGINT UNSIGNED NULL AFTER sample_id;
ALTER TABLE sample_images ADD COLUMN field_id BIGINT UNSIGNED NULL AFTER sample_id;

ALTER TABLE counts
    ADD CONSTRAINT fk_counts_field FOREIGN KEY (field_id) REFERENCES microscopic_fields(id) ON DELETE SET NULL;
ALTER TABLE sample_images
    ADD CONSTRAINT fk_images_field FOREIGN KEY (field_id) REFERENCES microscopic_fields(id) ON DELETE SET NULL;

-- Compatibilidade: transforma cada contagem histórica em um campo microscópico.
INSERT INTO microscopic_fields(sample_id,field_no,status,focus_score,quality_reason,included_in_summary,created_at)
SELECT c.sample_id,
       (
         SELECT COUNT(*)
         FROM counts c2
         WHERE c2.sample_id=c.sample_id AND c2.id<=c.id
       ) AS field_no,
       CASE
         WHEN UPPER(COALESCE(c.image_quality,'')) IN ('OK','ACEITA') THEN 'ACEITA'
         WHEN UPPER(COALESCE(c.image_quality,'')) IN ('DESFOCADA','REJEITADA','RUIM') THEN 'REJEITADA'
         ELSE 'REVISAR'
       END,
       c.focus_score,
       c.image_quality,
       CASE WHEN UPPER(COALESCE(c.image_quality,'')) IN ('DESFOCADA','REJEITADA','RUIM') THEN 0 ELSE 1 END,
       c.created_at
FROM counts c
LEFT JOIN microscopic_fields mf
  ON mf.sample_id=c.sample_id
 AND mf.field_no=(
   SELECT COUNT(*) FROM counts c2 WHERE c2.sample_id=c.sample_id AND c2.id<=c.id
 )
WHERE c.field_id IS NULL AND mf.id IS NULL;

UPDATE counts c
JOIN (
    SELECT c3.id count_id,mf.id field_id
    FROM counts c3
    JOIN microscopic_fields mf
      ON mf.sample_id=c3.sample_id
     AND mf.field_no=(
       SELECT COUNT(*) FROM counts c4 WHERE c4.sample_id=c3.sample_id AND c4.id<=c3.id
     )
) x ON x.count_id=c.id
SET c.field_id=x.field_id
WHERE c.field_id IS NULL;

UPDATE sample_images i
JOIN counts c ON c.id=i.count_id
SET i.field_id=c.field_id
WHERE i.field_id IS NULL;
