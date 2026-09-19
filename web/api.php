<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
api_authorize();

$action = (string)($_GET['action'] ?? $_POST['action'] ?? '');

try {
    if ($action === 'config') {
        $cfgInput=json_input();
        $sampleId=(int)($cfgInput['sample_id'] ?? $_GET['sample_id'] ?? 0);
        $items=db()->query(
            "SELECT id,code,name,category,color_hex,default_unit,ai_enabled,annotation_enabled,
                    summary_enabled,confidence_threshold,yolo_class_id,sort_order
             FROM count_item_types
             WHERE active=1
             ORDER BY sort_order,name"
        )->fetchAll();

        $protocols=db()->query(
            "SELECT cp.id,cp.code,cp.name,cp.min_fields,cp.min_valid_fields,cp.default_scale_label,
                    cp.default_magnification,cp.require_quality,cp.default_model_id,
                    m.code model_code,m.name model_name,m.version model_version,m.model_type,
                    m.status model_status,m.file_path model_path,m.sha256 model_sha256,
                    m.dataset_ref model_dataset,m.imgsz model_imgsz,m.epochs model_epochs
             FROM count_protocols cp
             LEFT JOIN ai_models m ON m.id=cp.default_model_id
             WHERE cp.active=1
             ORDER BY cp.name"
        )->fetchAll();

        $pitems=db()->query(
            "SELECT cpi.protocol_id,cit.id item_type_id,cit.code,cit.name,cit.color_hex,cit.default_unit,
                    cit.ai_enabled,cit.annotation_enabled,
                    COALESCE(cpi.confidence_threshold,cit.confidence_threshold) confidence_threshold,
                    COALESCE(cpi.summary_enabled,cit.summary_enabled) summary_enabled,
                    cpi.required_item,cpi.sort_order
             FROM count_protocol_items cpi
             JOIN count_item_types cit ON cit.id=cpi.item_type_id
             JOIN count_protocols cp ON cp.id=cpi.protocol_id
             WHERE cp.active=1 AND cit.active=1
             ORDER BY cpi.protocol_id,cpi.sort_order,cit.name"
        )->fetchAll();

        foreach($items as &$item){
            foreach(['id','ai_enabled','annotation_enabled','summary_enabled','sort_order'] as $key){
                $item[$key]=(int)$item[$key];
            }
            $item['confidence_threshold']=(float)$item['confidence_threshold'];
            $item['yolo_class_id']=$item['yolo_class_id']===null?null:(int)$item['yolo_class_id'];
        }
        unset($item);

        foreach($protocols as &$protocol){
            foreach(['id','min_fields','min_valid_fields','require_quality'] as $key){
                $protocol[$key]=(int)$protocol[$key];
            }
            $protocol['default_magnification']=$protocol['default_magnification']===null?null:(float)$protocol['default_magnification'];
            $protocol['default_model_id']=$protocol['default_model_id']===null?null:(int)$protocol['default_model_id'];
            $protocol['model_imgsz']=$protocol['model_imgsz']===null?null:(int)$protocol['model_imgsz'];
            $protocol['model_epochs']=$protocol['model_epochs']===null?null:(int)$protocol['model_epochs'];
        }
        unset($protocol);

        foreach($pitems as &$pi){
            foreach(['protocol_id','item_type_id','ai_enabled','annotation_enabled','summary_enabled','required_item','sort_order'] as $key){
                $pi[$key]=(int)$pi[$key];
            }
            $pi['confidence_threshold']=(float)$pi['confidence_threshold'];
        }
        unset($pi);

        $byProtocol=[];
        foreach($pitems as $row){
            $byProtocol[(int)$row['protocol_id']][]=$row;
        }
        foreach($protocols as &$protocol){
            $protocol['items']=$byProtocol[(int)$protocol['id']]??[];
        }
        unset($protocol);

        $sample=null;
        if($sampleId>0){
            $st=db()->prepare(
                "SELECT s.id,s.sample_code,s.protocol_id,cp.code protocol_code,cp.name protocol_name
                 FROM samples s
                 LEFT JOIN count_protocols cp ON cp.id=s.protocol_id
                 WHERE s.id=?"
            );
            $st->execute([$sampleId]);
            $sample=$st->fetch()?:null;
            if($sample){
                $sample['id']=(int)$sample['id'];
                $sample['protocol_id']=$sample['protocol_id']===null?null:(int)$sample['protocol_id'];
            }
        }

        json_response(['ok'=>true,'items'=>$items,'protocols'=>$protocols,'sample'=>$sample]);
    }

    if ($action === 'model_register') {
        $d=json_input();
        $code=strtolower(trim((string)($d['code']??'')));
        $name=trim((string)($d['name']??''));
        $version=trim((string)($d['version']??''));
        $filePath=trim((string)($d['file_path']??''));
        if(!preg_match('/^[a-z0-9_\-]+$/',$code) || $name==='' || $version==='' || $filePath===''){
            json_response(['ok'=>false,'error'=>'code, name, version e file_path são obrigatórios'],422);
        }
        $sha=strtolower(trim((string)($d['sha256']??'')));
        if($sha!==''&&!preg_match('/^[a-f0-9]{64}$/',$sha)){
            json_response(['ok'=>false,'error'=>'sha256 inválido'],422);
        }
        $status=(string)($d['status']??'VALIDACAO');
        if(!in_array($status,['TREINO','VALIDACAO','APROVADO','INATIVO'],true)){
            json_response(['ok'=>false,'error'=>'status inválido'],422);
        }
        $type=(string)($d['model_type']??'YOLO_SEG');
        if(!in_array($type,['YOLO_SEG','YOLO_DETECT','OUTRO'],true)){
            json_response(['ok'=>false,'error'=>'model_type inválido'],422);
        }
        $classes=is_array($d['classes']??null)?array_values($d['classes']):[];
        $pdo=db();
        $st=$pdo->prepare('SELECT id FROM ai_models WHERE code=? AND version=?');
        $st->execute([$code,$version]);
        $id=(int)($st->fetchColumn()?:0);
        if($id){
            $st=$pdo->prepare('UPDATE ai_models SET name=?,model_type=?,status=?,file_path=?,sha256=?,dataset_ref=?,imgsz=?,epochs=?,classes_json=?,trained_at=?,notes=? WHERE id=?');
            $st->execute([
                $name,$type,$status,$filePath,$sha?:null,$d['dataset_ref']??null,
                $d['imgsz']??null,$d['epochs']??null,
                json_encode($classes,JSON_UNESCAPED_UNICODE),
                $d['trained_at']??date('Y-m-d H:i:s'),$d['notes']??null,$id
            ]);
        }else{
            $st=$pdo->prepare('INSERT INTO ai_models(code,name,version,model_type,status,file_path,sha256,dataset_ref,imgsz,epochs,classes_json,trained_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)');
            $st->execute([
                $code,$name,$version,$type,$status,$filePath,$sha?:null,$d['dataset_ref']??null,
                $d['imgsz']??null,$d['epochs']??null,
                json_encode($classes,JSON_UNESCAPED_UNICODE),
                $d['trained_at']??date('Y-m-d H:i:s'),$d['notes']??null
            ]);
            $id=(int)$pdo->lastInsertId();
        }
        json_response(['ok'=>true,'model_id'=>$id]);
    }

    if ($action === 'model_metric_upsert') {
        $d=json_input();
        $modelId=(int)($d['model_id']??0);
        if($modelId<1) json_response(['ok'=>false,'error'=>'model_id obrigatório'],422);

        foreach(['precision','recall','f1','map50','map5095'] as $key){
            if(array_key_exists($key,$d) && $d[$key]!==null){
                $v=(float)$d[$key];
                if(!is_finite($v)||$v<0.0||$v>1.0){
                    json_response(['ok'=>false,'error'=>"{$key} deve estar entre 0 e 1"],422);
                }
            }
        }
        foreach(['mae','mape'] as $key){
            if(array_key_exists($key,$d) && $d[$key]!==null){
                $v=(float)$d[$key];
                if(!is_finite($v)||$v<0.0){
                    json_response(['ok'=>false,'error'=>"{$key} deve ser >= 0"],422);
                }
            }
        }
        if(array_key_exists('bias',$d) && $d['bias']!==null && !is_finite((float)$d['bias'])){
            json_response(['ok'=>false,'error'=>'bias inválido'],422);
        }
        if(array_key_exists('sample_count',$d) && $d['sample_count']!==null && (int)$d['sample_count']<0){
            json_response(['ok'=>false,'error'=>'sample_count deve ser >= 0'],422);
        }

        $code=trim((string)($d['component_code']??''));
        $itemTypeId=null;
        $scope='GERAL';
        if($code!==''){
            $st=db()->prepare('SELECT id FROM count_item_types WHERE code=?');
            $st->execute([$code]);
            $itemTypeId=(int)($st->fetchColumn()?:0);
            if($itemTypeId<1) json_response(['ok'=>false,'error'=>"Componente não encontrado: {$code}"],422);
            $scope='CLASSE';
        }
        if($itemTypeId){
            db()->prepare("DELETE FROM ai_model_metrics WHERE model_id=? AND item_type_id=? AND metric_scope='CLASSE'")->execute([$modelId,$itemTypeId]);
        }else{
            db()->prepare("DELETE FROM ai_model_metrics WHERE model_id=? AND item_type_id IS NULL AND metric_scope='GERAL'")->execute([$modelId]);
        }
        $st=db()->prepare('INSERT INTO ai_model_metrics(model_id,item_type_id,metric_scope,precision_value,recall_value,f1_value,map50_value,map5095_value,mae_value,bias_value,mape_value,sample_count,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)');
        $st->execute([
            $modelId,$itemTypeId,$scope,
            $d['precision']??null,$d['recall']??null,$d['f1']??null,$d['map50']??null,$d['map5095']??null,
            $d['mae']??null,$d['bias']??null,$d['mape']??null,$d['sample_count']??null,$d['notes']??null
        ]);
        json_response(['ok'=>true]);
    }

    if ($action === 'models_list') {
        $rows=db()->query(
            "SELECT m.id,m.code,m.name,m.version,m.model_type,m.status,m.file_path,m.sha256,m.dataset_ref,m.imgsz,m.epochs,m.trained_at,
                    mm.metric_scope,mm.precision_value,mm.recall_value,mm.f1_value,mm.map50_value,mm.map5095_value,mm.mae_value,mm.bias_value,mm.mape_value,mm.sample_count,
                    cit.code component_code,cit.name component_name
             FROM ai_models m
             LEFT JOIN ai_model_metrics mm ON mm.model_id=m.id
             LEFT JOIN count_item_types cit ON cit.id=mm.item_type_id
             ORDER BY m.code,m.version,mm.metric_scope,cit.sort_order,cit.name"
        )->fetchAll();
        $models=[];
        foreach($rows as $row){
            $id=(int)$row['id'];
            if(!isset($models[$id])){
                $models[$id]=[
                    'id'=>$id,'code'=>$row['code'],'name'=>$row['name'],'version'=>$row['version'],
                    'model_type'=>$row['model_type'],'status'=>$row['status'],'file_path'=>$row['file_path'],
                    'sha256'=>$row['sha256'],'dataset_ref'=>$row['dataset_ref'],'imgsz'=>$row['imgsz'],'epochs'=>$row['epochs'],
                    'trained_at'=>$row['trained_at'],'metrics'=>[]
                ];
            }
            if($row['metric_scope']){
                $models[$id]['metrics'][]=[
                    'scope'=>$row['metric_scope'],'component_code'=>$row['component_code'],'component_name'=>$row['component_name'],
                    'precision'=>$row['precision_value'],'recall'=>$row['recall_value'],'f1'=>$row['f1_value'],
                    'map50'=>$row['map50_value'],'map5095'=>$row['map5095_value'],'mae'=>$row['mae_value'],
                    'bias'=>$row['bias_value'],'mape'=>$row['mape_value'],'sample_count'=>$row['sample_count']
                ];
            }
        }
        json_response(['ok'=>true,'models'=>array_values($models)]);
    }

    if ($action === 'validation_data') {
        $d=json_input();
        $modelId=(int)($d['model_id']??$_GET['model_id']??0);
        if($modelId<1) json_response(['ok'=>false,'error'=>'model_id obrigatório'],422);

        $st=db()->prepare('SELECT id,code,name,version,status FROM ai_models WHERE id=?');
        $st->execute([$modelId]);
        $model=$st->fetch();
        if(!$model) json_response(['ok'=>false,'error'=>'Modelo não encontrado'],404);

        $st=db()->prepare(
            "SELECT i.id image_id,i.width_px,i.height_px,i.original_name,i.count_id,
                    s.id sample_id,s.patient_id
             FROM sample_images i
             JOIN counts c ON c.id=i.count_id
             JOIN samples s ON s.id=i.sample_id
             JOIN dataset_items di ON di.image_id=i.id
             WHERE c.model_id=?
               AND di.review_state IN ('REVISADA','APROVADA')
               AND EXISTS(
                 SELECT 1 FROM image_annotations ia
                 WHERE ia.image_id=i.id AND ia.source='MANUAL' AND ia.review_status='APROVADA'
               )
             ORDER BY i.id"
        );
        $st->execute([$modelId]);
        $images=[];
        foreach($st->fetchAll() as $img){
            $imageId=(int)$img['image_id'];

            $gtSt=db()->prepare(
                "SELECT class_code,polygon_json
                 FROM image_annotations
                 WHERE image_id=? AND source='MANUAL' AND review_status='APROVADA'
                 ORDER BY id"
            );
            $gtSt->execute([$imageId]);
            $gt=[];
            foreach($gtSt->fetchAll() as $row){
                $poly=json_decode((string)$row['polygon_json'],true);
                if(!is_array($poly)||count($poly)<3) continue;
                $gt[]=['class_code'=>$row['class_code'],'polygon'=>$poly];
            }

            $predSt=db()->prepare(
                'SELECT component_code,metadata_json FROM count_components WHERE count_id=? ORDER BY id'
            );
            $predSt->execute([(int)$img['count_id']]);
            $pred=[];
            foreach($predSt->fetchAll() as $row){
                $meta=json_decode((string)($row['metadata_json']??''),true);
                if(!is_array($meta)||!is_array($meta['detections']??null)) continue;
                foreach($meta['detections'] as $det){
                    $poly=$det['polygon']??null;
                    if(is_string($poly)){
                        $pts=[];
                        foreach(explode('|',$poly) as $token){
                            $xy=explode(':',$token,2);
                            if(count($xy)===2) $pts[]=[(float)$xy[0],(float)$xy[1]];
                        }
                        $poly=$pts;
                    }
                    if(!is_array($poly)||count($poly)<3){
                        $x1=(float)($det['x1']??0);$y1=(float)($det['y1']??0);
                        $x2=(float)($det['x2']??0);$y2=(float)($det['y2']??0);
                        if($x2>$x1 && $y2>$y1){
                            $poly=[[$x1,$y1],[$x2,$y1],[$x2,$y2],[$x1,$y2]];
                        }
                    }
                    if(!is_array($poly)||count($poly)<3) continue;
                    $pred[]=[
                        'class_code'=>(string)$row['component_code'],
                        'confidence'=>isset($det['confidence'])?(float)$det['confidence']:null,
                        'polygon'=>$poly,
                    ];
                }
            }

            $images[]=[
                'image_id'=>$imageId,
                'sample_id'=>(int)$img['sample_id'],
                'patient_id'=>(int)$img['patient_id'],
                'name'=>$img['original_name'],
                'width'=>(int)$img['width_px'],
                'height'=>(int)$img['height_px'],
                'ground_truth'=>$gt,
                'predictions'=>$pred,
            ];
        }

        json_response(['ok'=>true,'model'=>$model,'images'=>$images]);
    }

    if ($action === 'validation_run_register') {
        $d=json_input();
        $modelId=(int)($d['model_id']??0);
        if($modelId<1) json_response(['ok'=>false,'error'=>'model_id obrigatório'],422);
        $st=db()->prepare(
            'INSERT INTO ai_model_validation_runs(
                model_id,iou_threshold,reviewed_images,total_gt,total_predictions,
                true_positives,false_positives,false_negatives,
                precision_value,recall_value,f1_value,mae_value,bias_value,mape_value,
                class_metrics_json,config_json,notes
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
        );
        $st->execute([
            $modelId,
            $d['iou_threshold']??0.5,
            $d['reviewed_images']??0,
            $d['total_gt']??0,
            $d['total_predictions']??0,
            $d['tp']??0,
            $d['fp']??0,
            $d['fn']??0,
            $d['precision']??null,
            $d['recall']??null,
            $d['f1']??null,
            $d['mae']??null,
            $d['bias']??null,
            $d['mape']??null,
            json_encode($d['class_metrics']??[],JSON_UNESCAPED_UNICODE),
            json_encode($d['config']??[],JSON_UNESCAPED_UNICODE),
            $d['notes']??null,
        ]);
        json_response(['ok'=>true,'validation_run_id'=>(int)db()->lastInsertId()]);
    }

    if ($action === 'annotations_save') {
        $d=json_input();
        $imageId=(int)($d['image_id']??0);
        $items=is_array($d['annotations']??null)?$d['annotations']:[];
        if($imageId<1) json_response(['ok'=>false,'error'=>'image_id obrigatório'],422);
        if(count($items)>5000) json_response(['ok'=>false,'error'=>'Limite de 5000 anotações por imagem excedido'],422);

        $st=db()->prepare('SELECT id,width_px,height_px FROM sample_images WHERE id=?');
        $st->execute([$imageId]);
        $image=$st->fetch();
        if(!$image) json_response(['ok'=>false,'error'=>'Imagem não encontrada'],404);

        $normalize=function(string $value): string {
            $v=strtolower(trim($value));
            $v=strtr($v,[
                'á'=>'a','à'=>'a','ã'=>'a','â'=>'a','ä'=>'a',
                'é'=>'e','è'=>'e','ê'=>'e','ë'=>'e',
                'í'=>'i','ì'=>'i','î'=>'i','ï'=>'i',
                'ó'=>'o','ò'=>'o','õ'=>'o','ô'=>'o','ö'=>'o',
                'ú'=>'u','ù'=>'u','û'=>'u','ü'=>'u','ç'=>'c'
            ]);
            $aliases=[
                'rbc'=>'hemacia','red blood cell'=>'hemacia','red_blood_cell'=>'hemacia',
                'wbc'=>'leucocito','white blood cell'=>'leucocito','white_blood_cell'=>'leucocito',
                'platelet'=>'plaqueta','artifact'=>'artefato'
            ];
            return $aliases[$v]??$v;
        };

        $width=max(1,(int)$image['width_px']);
        $height=max(1,(int)$image['height_px']);
        $clean=[];
        $stType=db()->prepare(
            'SELECT id,code,name FROM count_item_types WHERE code=? AND active=1 AND annotation_enabled=1'
        );
        foreach($items as $idx=>$item){
            $code=$normalize((string)($item['class_code']??''));
            $stType->execute([$code]);
            $type=$stType->fetch();
            if(!$type) json_response(['ok'=>false,'error'=>"Classe inválida na anotação {$idx}"],422);
            $polygon=$item['polygon']??null;
            if(!is_array($polygon)||count($polygon)<3||count($polygon)>2000){
                json_response(['ok'=>false,'error'=>"Polígono inválido na anotação {$idx}"],422);
            }
            $points=[];
            foreach($polygon as $p){
                if(!is_array($p)||count($p)<2) json_response(['ok'=>false,'error'=>"Ponto inválido na anotação {$idx}"],422);
                $x=(float)$p[0];$y=(float)$p[1];
                if(!is_finite($x)||!is_finite($y)||$x<0||$x>$width||$y<0||$y>$height){
                    json_response(['ok'=>false,'error'=>"Ponto fora da imagem na anotação {$idx}"],422);
                }
                $points[]=[$x,$y];
            }
            $clean[]=[
                'item_type_id'=>(int)$type['id'],
                'class_code'=>(string)$type['code'],
                'class_name'=>(string)$type['name'],
                'polygon'=>$points,
                'notes'=>trim((string)($item['notes']??''))?:'Revisão realizada no cliente Lazarus'
            ];
        }

        $pdo=db();
        $pdo->beginTransaction();
        try{
            $pdo->prepare('DELETE FROM image_annotations WHERE image_id=?')->execute([$imageId]);
            $ins=$pdo->prepare(
                "INSERT INTO image_annotations(image_id,item_type_id,class_code,class_name,polygon_json,source,review_status,notes)
                 VALUES(?,?,?,?,?,'MANUAL','APROVADA',?)"
            );
            foreach($clean as $item){
                $ins->execute([
                    $imageId,$item['item_type_id'],$item['class_code'],$item['class_name'],
                    json_encode($item['polygon'],JSON_UNESCAPED_UNICODE),$item['notes']
                ]);
            }
            $pdo->prepare(
                "INSERT INTO dataset_items(image_id,review_state,reviewed_at)
                 VALUES(?,'REVISADA',NOW())
                 ON DUPLICATE KEY UPDATE review_state='REVISADA',reviewed_at=NOW()"
            )->execute([$imageId]);
            $pdo->prepare(
                "INSERT INTO annotation_revisions(image_id,user_id,action_type,details_json)
                 VALUES(?,NULL,'SAVE_LAZARUS',?)"
            )->execute([
                $imageId,json_encode(['count'=>count($clean),'source'=>'LAZARUS'],JSON_UNESCAPED_UNICODE)
            ]);
            $pdo->commit();
        }catch(Throwable $e){
            if($pdo->inTransaction())$pdo->rollBack();
            throw $e;
        }

        json_response(['ok'=>true,'saved'=>count($clean),'image_id'=>$imageId,'review_state'=>'REVISADA']);
    }

    if ($action === 'sample_summary') {
        $d=json_input();
        $sampleId=(int)($d['sample_id']??$_GET['sample_id']??0);
        if($sampleId<1) json_response(['ok'=>false,'error'=>'sample_id obrigatório'],422);

        $st=db()->prepare(
            'SELECT s.id,s.sample_code,s.patient_id,p.name patient_name,
                    cp.id protocol_id,cp.code protocol_code,cp.name protocol_name,
                    cp.min_fields,cp.min_valid_fields,cp.require_quality
             FROM samples s
             JOIN patients p ON p.id=s.patient_id
             LEFT JOIN count_protocols cp ON cp.id=s.protocol_id
             WHERE s.id=?'
        );
        $st->execute([$sampleId]);
        $sample=$st->fetch();
        if(!$sample) json_response(['ok'=>false,'error'=>'Amostra não encontrada'],404);

        $st=db()->prepare(
            'SELECT mf.id,mf.field_no,mf.status,mf.quality_score,mf.focus_score,
                    mf.quality_reason,mf.included_in_summary,
                    c.id count_id,c.method,c.algorithm_version,c.image_quality,c.total_cells,c.created_at,
                    i.id image_id,i.original_name
             FROM microscopic_fields mf
             LEFT JOIN counts c ON c.field_id=mf.id
             LEFT JOIN sample_images i ON i.field_id=mf.id
             WHERE mf.sample_id=?
             ORDER BY mf.field_no'
        );
        $st->execute([$sampleId]);
        $fields=$st->fetchAll();

        $st=db()->prepare(
            "SELECT cc.component_code,cc.component_name,cc.quantity,mf.field_no
             FROM microscopic_fields mf
             JOIN counts c ON c.field_id=mf.id
             JOIN count_components cc ON cc.count_id=c.id
             LEFT JOIN count_item_types cit ON cit.id=cc.item_type_id
             LEFT JOIN count_protocol_items cpi ON cpi.item_type_id=cc.item_type_id
               AND cpi.protocol_id=(SELECT protocol_id FROM samples WHERE id=?)
             WHERE mf.sample_id=? AND mf.status='ACEITA' AND mf.included_in_summary=1
               AND COALESCE(cpi.summary_enabled,cit.summary_enabled,1)=1
             ORDER BY cc.component_code,mf.field_no"
        );
        $st->execute([$sampleId,$sampleId]);
        $rows=$st->fetchAll();

        $grouped=[];
        foreach($rows as $row){
            $code=(string)$row['component_code'];
            $grouped[$code]['code']=$code;
            $grouped[$code]['name']=$row['component_name'];
            $grouped[$code]['values'][]=(float)$row['quantity'];
        }
        $medianFn=function(array $values): float {
            sort($values,SORT_NUMERIC);$n=count($values);
            if($n===0)return 0.0;$m=intdiv($n,2);
            return $n%2?$values[$m]:($values[$m-1]+$values[$m])/2;
        };
        $stdFn=function(array $values): float {
            $n=count($values);if($n<2)return 0.0;
            $mean=array_sum($values)/$n;$sum=0.0;
            foreach($values as $v)$sum+=($v-$mean)**2;
            return sqrt($sum/($n-1));
        };
        $summary=[];
        foreach($grouped as $g){
            $v=$g['values'];$n=count($v);
            $summary[]=[
                'code'=>$g['code'],'name'=>$g['name'],'fields'=>$n,
                'mean'=>$n?array_sum($v)/$n:0.0,
                'median'=>$medianFn($v),
                'min'=>$n?min($v):0.0,'max'=>$n?max($v):0.0,
                'stddev'=>$stdFn($v),
            ];
        }

        $accepted=0;$rejected=0;$review=0;
        foreach($fields as &$field){
            $field['id']=(int)$field['id'];
            $field['field_no']=(int)$field['field_no'];
            $field['included_in_summary']=(int)$field['included_in_summary'];
            $field['quality_score']=$field['quality_score']===null?null:(float)$field['quality_score'];
            $field['focus_score']=$field['focus_score']===null?null:(float)$field['focus_score'];
            if($field['status']==='ACEITA' && $field['included_in_summary'])$accepted++;
            elseif($field['status']==='REJEITADA' || !$field['included_in_summary'])$rejected++;
            else $review++;
        }
        unset($field);

        $minFields=(int)($sample['min_fields']??0);
        $minValid=(int)($sample['min_valid_fields']??0);
        $ready=($minValid===0 || $accepted>=$minValid) && ($minFields===0 || count($fields)>=$minFields);

        json_response([
            'ok'=>true,'sample'=>$sample,'fields'=>$fields,'summary'=>$summary,
            'totals'=>[
                'fields'=>count($fields),'accepted'=>$accepted,
                'rejected'=>$rejected,'review'=>$review,
                'min_fields'=>$minFields,'min_valid_fields'=>$minValid,
                'ready'=>$ready
            ]
        ]);
    }

    if ($action === 'patient_upsert') {
        $d = json_input();
        $name = trim((string)($d['name'] ?? ''));
        if ($name === '') json_response(['ok'=>false,'error'=>'name obrigatório'], 422);

        $externalId = trim((string)($d['external_id'] ?? ''));
        $pdo = db();

        if ($externalId !== '') {
            $st = $pdo->prepare('SELECT id FROM patients WHERE external_id=?');
            $st->execute([$externalId]);
            $id = $st->fetchColumn();
            if ($id) {
                $st = $pdo->prepare('UPDATE patients SET name=?,birth_date=?,sex=?,document=?,notes=? WHERE id=?');
                $st->execute([
                    $name, $d['birth_date'] ?? null, $d['sex'] ?? null,
                    $d['document'] ?? null, $d['notes'] ?? null, (int)$id
                ]);
                json_response(['ok'=>true,'patient_id'=>(int)$id,'updated'=>true]);
            }
        }

        $st = $pdo->prepare('INSERT INTO patients(external_id,name,birth_date,sex,document,notes) VALUES(?,?,?,?,?,?)');
        $st->execute([
            $externalId !== '' ? $externalId : null,
            $name, $d['birth_date'] ?? null, $d['sex'] ?? null,
            $d['document'] ?? null, $d['notes'] ?? null
        ]);
        json_response(['ok'=>true,'patient_id'=>(int)$pdo->lastInsertId(),'updated'=>false]);
    }

    if ($action === 'sample_create') {
        $d = json_input();
        $patientId = (int)($d['patient_id'] ?? 0);
        $code = trim((string)($d['sample_code'] ?? ''));
        if ($patientId < 1 || $code === '') {
            json_response(['ok'=>false,'error'=>'patient_id e sample_code obrigatórios'], 422);
        }

        $pdo = db();
        $protocolId=(int)($d['protocol_id']??0);
        $protocolCode=trim((string)($d['protocol_code']??''));
        if($protocolId<1 && $protocolCode!==''){
            $st=$pdo->prepare('SELECT id FROM count_protocols WHERE code=? AND active=1');
            $st->execute([$protocolCode]);
            $protocolId=(int)($st->fetchColumn()?:0);
        }
        if($protocolId<1){
            $protocolId=(int)($pdo->query("SELECT id FROM count_protocols WHERE active=1 ORDER BY id LIMIT 1")->fetchColumn()?:0);
        }

        $st = $pdo->prepare('SELECT id FROM samples WHERE patient_id=? AND sample_code=?');
        $st->execute([$patientId, $code]);
        $id = $st->fetchColumn();
        if ($id) json_response(['ok'=>true,'sample_id'=>(int)$id,'existing'=>true]);

        $st = $pdo->prepare(
            'INSERT INTO samples(patient_id,protocol_id,sample_code,collected_at,sample_type,notes)
             VALUES(?,?,?,?,?,?)'
        );
        $st->execute([
            $patientId, $protocolId ?: null, $code, $d['collected_at'] ?? null,
            $d['sample_type'] ?? 'sangue', $d['notes'] ?? null
        ]);
        json_response(['ok'=>true,'sample_id'=>(int)$pdo->lastInsertId(),'existing'=>false]);
    }

    if ($action === 'count_create') {
        $pdo = db();
        $payload = $_POST['payload'] ?? '';
        if($payload!==''){
            $d = json_decode((string)$payload, true);
        }else{
            $d = json_input();
        }
        if (!is_array($d)) json_response(['ok'=>false,'error'=>'payload JSON inválido'], 422);

        $sampleId = (int)($d['sample_id'] ?? 0);
        if ($sampleId < 1) json_response(['ok'=>false,'error'=>'sample_id obrigatório'], 422);

        $pdo->beginTransaction();

        $st = $pdo->prepare(
            'SELECT COALESCE(MAX(field_no),0)+1
             FROM microscopic_fields
             WHERE sample_id=? FOR UPDATE'
        );
        $st->execute([$sampleId]);
        $fieldNo = (int)$st->fetchColumn();

        $quality = strtoupper((string)($d['image_quality'] ?? 'REVISAR'));
        $fieldStatus = in_array($quality, ['ACEITA','REJEITADA','REVISAR'], true)
            ? $quality
            : 'REVISAR';
        $included = $fieldStatus === 'REJEITADA' ? 0 : 1;

        $st = $pdo->prepare(
            'INSERT INTO microscopic_fields(
                sample_id,field_no,status,quality_score,focus_score,
                quality_reason,included_in_summary
             ) VALUES(?,?,?,?,?,?,?)'
        );
        $st->execute([
            $sampleId,
            $fieldNo,
            $fieldStatus,
            $d['quality_score'] ?? null,
            $d['focus_score'] ?? null,
            $d['quality_reason'] ?? null,
            $included,
        ]);
        $fieldId = (int)$pdo->lastInsertId();

        $modelId=(int)($d['model_id']??0);
        $modelVersion=null;
        $modelSha=strtolower(trim((string)($d['model_sha256']??'')))?:null;
        $modelPath=trim((string)($d['model_path']??''))?:null;
        if($modelSha!==null && !preg_match('/^[a-f0-9]{64}$/',$modelSha)){
            throw new RuntimeException('SHA-256 do modelo inválido.');
        }
        if($modelId>0){
            $stExpected=$pdo->prepare(
                'SELECT cp.default_model_id
                 FROM samples s
                 LEFT JOIN count_protocols cp ON cp.id=s.protocol_id
                 WHERE s.id=?'
            );
            $stExpected->execute([$sampleId]);
            $expectedModelId=(int)($stExpected->fetchColumn()?:0);
            if($expectedModelId!==$modelId){
                throw new RuntimeException('Modelo informado não corresponde ao modelo padrão do protocolo.');
            }

            $stModel=$pdo->prepare("SELECT version,sha256,status FROM ai_models WHERE id=? AND status IN ('VALIDACAO','APROVADO')");
            $stModel->execute([$modelId]);
            $modelRow=$stModel->fetch();
            if(!$modelRow) throw new RuntimeException('Modelo informado não existe ou não está liberado para uso.');
            $modelVersion=(string)$modelRow['version'];
            $registeredSha=strtolower(trim((string)($modelRow['sha256']??'')));
            if($registeredSha!=='' && $modelSha!==null && $modelSha!==$registeredSha){
                throw new RuntimeException('SHA-256 informado não corresponde ao modelo cadastrado.');
            }
            $modelSha=$registeredSha!=='' ? $registeredSha : $modelSha;
        }

        $sourceClient=strtoupper(trim((string)($d['source_client']??'PYTHON')));
        if(!in_array($sourceClient,['PYTHON','LAZARUS'],true)){
            $sourceClient='PYTHON';
        }

        $st = $pdo->prepare(
            'INSERT INTO counts(
                sample_id,field_id,method,algorithm_version,model_id,model_version_snapshot,model_sha256_snapshot,model_path_snapshot,
                scale_label,magnification,pixel_size_um,focus_score,image_quality,total_cells,notes,source
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
        );
        $st->execute([
            $sampleId,
            $fieldId,
            $d['method'] ?? 'opencv-hough',
            $d['algorithm_version'] ?? null,
            $modelId?:null,$modelVersion,$modelSha,$modelPath,
            $d['scale_label'] ?? null,
            $d['magnification'] ?? null,
            $d['pixel_size_um'] ?? null,
            $d['focus_score'] ?? null,
            $fieldStatus,
            $d['total_cells'] ?? null,
            $d['notes'] ?? null,
            $sourceClient,
        ]);
        $countId = (int)$pdo->lastInsertId();

        $components = is_array($d['components'] ?? null) ? $d['components'] : [];
        $stProtocol=$pdo->prepare('SELECT protocol_id FROM samples WHERE id=?');
        $stProtocol->execute([$sampleId]);
        $sampleProtocolId=(int)($stProtocol->fetchColumn()?:0);

        $stType=$pdo->prepare(
            'SELECT cit.id,cit.name,cit.default_unit,
                    COALESCE(cpi.confidence_threshold,cit.confidence_threshold) confidence_threshold
             FROM count_item_types cit
             LEFT JOIN count_protocol_items cpi
               ON cpi.item_type_id=cit.id AND cpi.protocol_id=?
             WHERE cit.code=? AND cit.active=1
               AND (?=0 OR cpi.protocol_id IS NOT NULL)'
        );
        $stComp = $pdo->prepare(
            'INSERT INTO count_components(
                count_id,item_type_id,component_code,component_name,quantity,unit,confidence,metadata_json
             ) VALUES(?,?,?,?,?,?,?,?)'
        );
        foreach ($components as $component) {
            $componentCode=strtolower(trim((string)($component['code'] ?? 'outro')));
            $stType->execute([$sampleProtocolId,$componentCode,$sampleProtocolId]);
            $type=$stType->fetch();
            if(!$type){
                throw new RuntimeException("Componente não permitido pelo protocolo: {$componentCode}");
            }

            $confidence=isset($component['confidence']) ? (float)$component['confidence'] : null;
            $threshold=(float)$type['confidence_threshold'];
            if($confidence!==null && $confidence<$threshold){
                throw new RuntimeException(
                    "Confiança média abaixo do limiar para {$componentCode}: {$confidence} < {$threshold}"
                );
            }

            $stComp->execute([
                $countId,
                (int)$type['id'],
                $componentCode,
                (string)$type['name'],
                max(0, (int)($component['quantity'] ?? 0)),
                (string)$type['default_unit'],
                $confidence,
                isset($component['metadata'])
                    ? json_encode($component['metadata'], JSON_UNESCAPED_UNICODE)
                    : null,
            ]);
        }

        $imageId = null;
        $imageTempPath=null;
        $imageOriginalName=null;
        $imageSize=0;
        $moveUploaded=false;

        if (!empty($_FILES['image']) && is_uploaded_file($_FILES['image']['tmp_name'])) {
            $file = $_FILES['image'];
            $imageTempPath=(string)$file['tmp_name'];
            $imageOriginalName=basename((string)$file['name']);
            $imageSize=(int)$file['size'];
            $moveUploaded=true;
        } elseif (!empty($d['image_base64'])) {
            $raw=base64_decode((string)$d['image_base64'],true);
            if($raw===false){
                throw new RuntimeException('Imagem Base64 inválida.');
            }
            $imageSize=strlen($raw);
            $imageOriginalName=basename((string)($d['image_name']??'lamina.png'));
            $imageTempPath=tempnam(sys_get_temp_dir(),'hemacias_img_');
            if($imageTempPath===false || file_put_contents($imageTempPath,$raw)===false){
                throw new RuntimeException('Falha ao preparar imagem enviada em Base64.');
            }
        }

        if($imageTempPath!==null){
            try{
                if ($imageSize > (int)$config['app']['max_upload_bytes']) {
                    throw new RuntimeException('Imagem excede o limite configurado.');
                }

                $finfo = new finfo(FILEINFO_MIME_TYPE);
                $mime = $finfo->file($imageTempPath);
                $allowed = ['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp'];
                if (!isset($allowed[$mime])) {
                    throw new RuntimeException('Formato de imagem não permitido.');
                }

                $dir = rtrim((string)$config['app']['upload_dir'], '/\\') . '/' . date('Y/m');
                if (!is_dir($dir) && !mkdir($dir, 0770, true) && !is_dir($dir)) {
                    throw new RuntimeException('Não foi possível criar diretório de upload.');
                }

                $stored = bin2hex(random_bytes(16)) . '.' . $allowed[$mime];
                $dest = $dir . '/' . $stored;
                if($moveUploaded){
                    if (!move_uploaded_file($imageTempPath, $dest)) {
                        throw new RuntimeException('Falha ao armazenar imagem.');
                    }
                }else{
                    if(!rename($imageTempPath,$dest)){
                        if(!copy($imageTempPath,$dest)){
                            throw new RuntimeException('Falha ao armazenar imagem Base64.');
                        }
                        @unlink($imageTempPath);
                    }
                    $imageTempPath=null;
                }

                [$width, $height] = getimagesize($dest) ?: [null, null];
                $relative = date('Y/m') . '/' . $stored;
                $sha = hash_file('sha256', $dest);

                $stImg = $pdo->prepare(
                    'INSERT INTO sample_images(
                        sample_id,field_id,count_id,original_name,stored_name,mime_type,file_size,sha256,
                        width_px,height_px,scale_label,magnification
                     ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)'
                );
                $stImg->execute([
                    $sampleId,
                    $fieldId,
                    $countId,
                    $imageOriginalName,
                    $relative,
                    $mime,
                    $imageSize,
                    $sha,
                    $width,
                    $height,
                    $d['scale_label'] ?? null,
                    $d['magnification'] ?? null,
                ]);
                $imageId = (int)$pdo->lastInsertId();
            } finally {
                if(!$moveUploaded && $imageTempPath!==null && is_file($imageTempPath)){
                    @unlink($imageTempPath);
                }
            }
        }

        $pdo->commit();
        json_response([
            'ok'=>true,
            'count_id'=>$countId,
            'image_id'=>$imageId,
            'field_id'=>$fieldId,
            'field_no'=>$fieldNo,
            'field_status'=>$fieldStatus,
        ]);
    }

    if ($action === 'patient_search') {
        $q = trim((string)($_GET['q'] ?? ''));
        $st = db()->prepare(
            'SELECT id,external_id,name,birth_date FROM patients
             WHERE name LIKE ? OR external_id LIKE ? ORDER BY name LIMIT 20'
        );
        $like = '%' . $q . '%';
        $st->execute([$like, $like]);
        json_response(['ok'=>true,'patients'=>$st->fetchAll()]);
    }

    json_response(['ok'=>false,'error'=>'Ação não encontrada'], 404);
} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    json_response(['ok'=>false,'error'=>$e->getMessage()], 500);
}
