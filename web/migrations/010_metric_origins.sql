USE hemacias;

ALTER TABLE ai_model_metrics
  ADD COLUMN metric_origin ENUM('TRAINING','COUNT_REFERENCE','GROUND_TRUTH','MANUAL') NOT NULL DEFAULT 'MANUAL'
  AFTER metric_scope;

ALTER TABLE ai_model_metrics
  DROP INDEX uq_ai_metric_scope;

ALTER TABLE ai_model_metrics
  ADD UNIQUE KEY uq_ai_metric_scope_origin(model_id,item_type_id,metric_scope,metric_origin);
