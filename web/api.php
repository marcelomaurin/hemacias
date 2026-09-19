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
        $d = json_decode((string)$payload, true);
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
            $modelSha=$modelRow['sha256'] ?: $modelSha;
        }

        $st = $pdo->prepare(
            'INSERT INTO counts(
                sample_id,field_id,method,algorithm_version,model_id,model_version_snapshot,model_sha256_snapshot,model_path_snapshot,
                scale_label,magnification,pixel_size_um,focus_score,image_quality,total_cells,notes,source
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,\'PYTHON\')'
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
        if (!empty($_FILES['image']) && is_uploaded_file($_FILES['image']['tmp_name'])) {
            $file = $_FILES['image'];
            if ((int)$file['size'] > (int)$config['app']['max_upload_bytes']) {
                throw new RuntimeException('Imagem excede o limite configurado.');
            }

            $finfo = new finfo(FILEINFO_MIME_TYPE);
            $mime = $finfo->file($file['tmp_name']);
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
            if (!move_uploaded_file($file['tmp_name'], $dest)) {
                throw new RuntimeException('Falha ao armazenar imagem.');
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
                basename((string)$file['name']),
                $relative,
                $mime,
                (int)$file['size'],
                $sha,
                $width,
                $height,
                $d['scale_label'] ?? null,
                $d['magnification'] ?? null,
            ]);
            $imageId = (int)$pdo->lastInsertId();
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
