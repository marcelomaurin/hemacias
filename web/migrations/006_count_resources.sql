USE hemacias;

CREATE TABLE IF NOT EXISTS count_item_types (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(60) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL,
    category VARCHAR(60) NOT NULL DEFAULT 'CELULA',
    active TINYINT(1) NOT NULL DEFAULT 1,
    color_hex CHAR(7) NOT NULL DEFAULT '#00ff00',
    default_unit VARCHAR(60) NOT NULL DEFAULT 'objetos/campo',
    ai_enabled TINYINT(1) NOT NULL DEFAULT 1,
    annotation_enabled TINYINT(1) NOT NULL DEFAULT 1,
    summary_enabled TINYINT(1) NOT NULL DEFAULT 1,
    confidence_threshold DECIMAL(6,4) NOT NULL DEFAULT 0.2500,
    yolo_class_id INT NULL,
    sort_order INT NOT NULL DEFAULT 100,
    notes VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_count_item_active (active,sort_order)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS count_protocols (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(60) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    min_fields INT UNSIGNED NOT NULL DEFAULT 5,
    min_valid_fields INT UNSIGNED NOT NULL DEFAULT 3,
    default_scale_label VARCHAR(80) NULL,
    default_magnification DECIMAL(10,3) NULL,
    require_quality TINYINT(1) NOT NULL DEFAULT 1,
    notes VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS count_protocol_items (
    protocol_id BIGINT UNSIGNED NOT NULL,
    item_type_id BIGINT UNSIGNED NOT NULL,
    required_item TINYINT(1) NOT NULL DEFAULT 0,
    confidence_threshold DECIMAL(6,4) NULL,
    summary_enabled TINYINT(1) NULL,
    sort_order INT NOT NULL DEFAULT 100,
    PRIMARY KEY(protocol_id,item_type_id),
    CONSTRAINT fk_protocol_items_protocol FOREIGN KEY(protocol_id) REFERENCES count_protocols(id) ON DELETE CASCADE,
    CONSTRAINT fk_protocol_items_type FOREIGN KEY(item_type_id) REFERENCES count_item_types(id) ON DELETE CASCADE
) ENGINE=InnoDB;

ALTER TABLE samples ADD COLUMN protocol_id BIGINT UNSIGNED NULL AFTER patient_id;
ALTER TABLE samples ADD CONSTRAINT fk_samples_protocol FOREIGN KEY(protocol_id) REFERENCES count_protocols(id) ON DELETE SET NULL;

ALTER TABLE count_components ADD COLUMN item_type_id BIGINT UNSIGNED NULL AFTER count_id;
ALTER TABLE count_components ADD CONSTRAINT fk_count_components_item_type FOREIGN KEY(item_type_id) REFERENCES count_item_types(id) ON DELETE SET NULL;

ALTER TABLE image_annotations ADD COLUMN item_type_id BIGINT UNSIGNED NULL AFTER image_id;
ALTER TABLE image_annotations ADD CONSTRAINT fk_annotations_item_type FOREIGN KEY(item_type_id) REFERENCES count_item_types(id) ON DELETE SET NULL;

INSERT INTO count_item_types(code,name,category,color_hex,default_unit,ai_enabled,annotation_enabled,summary_enabled,confidence_threshold,yolo_class_id,sort_order)
VALUES
('hemacia','Hemácia','CELULA','#00ff00','células/campo',1,1,1,0.2500,0,10),
('leucocito','Leucócito','CELULA','#00b7ff','células/campo',1,1,1,0.3000,1,20),
('plaqueta','Plaqueta','FRAGMENTO','#ffd000','objetos/campo',1,1,1,0.3500,2,30),
('artefato','Artefato','ARTEFATO','#ff3b30','objetos/campo',1,1,0,0.2500,3,90),
('outro','Outro','OUTRO','#ffffff','objetos/campo',0,1,0,0.2500,4,100)
ON DUPLICATE KEY UPDATE name=VALUES(name);

INSERT INTO count_protocols(code,name,min_fields,min_valid_fields,default_scale_label,default_magnification,require_quality,notes)
VALUES('sangue_padrao','Contagem sanguínea experimental',10,8,'40x',40,1,'Protocolo inicial multiclasse')
ON DUPLICATE KEY UPDATE name=VALUES(name);

INSERT INTO count_protocol_items(protocol_id,item_type_id,required_item,confidence_threshold,summary_enabled,sort_order)
SELECT p.id,t.id,
       CASE WHEN t.code IN ('hemacia','leucocito','plaqueta') THEN 1 ELSE 0 END,
       t.confidence_threshold,
       t.summary_enabled,
       t.sort_order
FROM count_protocols p
JOIN count_item_types t
WHERE p.code='sangue_padrao'
ON DUPLICATE KEY UPDATE
  required_item=VALUES(required_item),
  confidence_threshold=VALUES(confidence_threshold),
  summary_enabled=VALUES(summary_enabled),
  sort_order=VALUES(sort_order);

UPDATE samples
SET protocol_id=(SELECT id FROM count_protocols WHERE code='sangue_padrao' LIMIT 1)
WHERE protocol_id IS NULL;

UPDATE count_components cc
JOIN count_item_types t ON t.code=cc.component_code
SET cc.item_type_id=t.id
WHERE cc.item_type_id IS NULL;

UPDATE image_annotations ia
JOIN count_item_types t ON t.code=ia.class_code
SET ia.item_type_id=t.id
WHERE ia.item_type_id IS NULL;
