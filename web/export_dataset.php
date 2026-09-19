<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
require_login();

if(!class_exists('ZipArchive')){
    http_response_code(500);
    exit('Extensão PHP ZipArchive não instalada.');
}

$classes=[];
foreach(db()->query(
    "SELECT code,name,yolo_class_id
     FROM count_item_types
     WHERE active=1 AND annotation_enabled=1 AND yolo_class_id IS NOT NULL
     ORDER BY yolo_class_id,sort_order,name"
)->fetchAll() as $row){
    $classes[$row['code']]=[
        'id'=>(int)$row['yolo_class_id'],
        'name'=>(string)$row['code'],
        'display_name'=>(string)$row['name'],
    ];
}

$st=db()->query(
    "SELECT i.*,d.split_set
     FROM sample_images i
     JOIN dataset_items d ON d.image_id=i.id
     WHERE d.review_state='APROVADA' AND d.included=1
       AND d.split_set IN ('TRAIN','VAL','TEST')
     ORDER BY i.id"
);
$images=$st->fetchAll();

if(!$images){
    http_response_code(422);
    exit('Não há imagens aprovadas, incluídas e com split definido para exportar.');
}

// Pré-validação científica e estrutural do dataset.
$splitCounts=['TRAIN'=>0,'VAL'=>0,'TEST'=>0];
$patientSplits=[];
$sampleSplits=[];
$problems=[];
$classIds=[];

foreach($classes as $code=>$meta){
    $id=(int)$meta['id'];
    if(isset($classIds[$id]) && $classIds[$id]!==$code){
        $problems[]="ID YOLO duplicado {$id}: {$classIds[$id]} e {$code}.";
    }
    $classIds[$id]=$code;
}

$stMeta=db()->prepare(
    "SELECT i.id,i.width_px,i.height_px,i.stored_name,d.split_set,s.id sample_id,p.id patient_id
     FROM sample_images i
     JOIN dataset_items d ON d.image_id=i.id
     JOIN samples s ON s.id=i.sample_id
     JOIN patients p ON p.id=s.patient_id
     WHERE i.id=?"
);
$stPending=db()->prepare(
    "SELECT COUNT(*) FROM image_annotations
     WHERE image_id=? AND review_status<>'APROVADA'"
);
$stAnn=db()->prepare(
    "SELECT class_code,polygon_json FROM image_annotations
     WHERE image_id=? AND review_status='APROVADA'"
);

foreach($images as $image){
    $imageId=(int)$image['id'];
    $split=(string)$image['split_set'];
    $splitCounts[$split]++;

    $stMeta->execute([$imageId]);
    $meta=$stMeta->fetch();
    if(!$meta){$problems[]="Imagem {$imageId} sem metadados.";continue;}

    $patientSplits[(int)$meta['patient_id']][$split]=true;
    $sampleSplits[(int)$meta['sample_id']][$split]=true;

    if((int)$meta['width_px']<1 || (int)$meta['height_px']<1){
        $problems[]="Imagem {$imageId} sem dimensões válidas.";
    }

    $stPending->execute([$imageId]);
    if((int)$stPending->fetchColumn()>0){
        $problems[]="Imagem {$imageId} possui anotações ainda não aprovadas.";
    }

    $stAnn->execute([$imageId]);
    foreach($stAnn->fetchAll() as $a){
        $code=(string)$a['class_code'];
        if(!isset($classes[$code])){
            $problems[]="Imagem {$imageId}: classe {$code} não possui ID YOLO ativo.";
            continue;
        }
        $points=json_decode((string)$a['polygon_json'],true);
        if(!is_array($points) || count($points)<3){
            $problems[]="Imagem {$imageId}: polígono inválido na classe {$code}.";
        }
    }
}

foreach($patientSplits as $patientId=>$splits){
    if(count($splits)>1){
        $problems[]="Vazamento: paciente {$patientId} aparece em mais de um split (".implode(',',array_keys($splits)).").";
    }
}
foreach($sampleSplits as $sampleId=>$splits){
    if(count($splits)>1){
        $problems[]="Vazamento: amostra {$sampleId} aparece em mais de um split (".implode(',',array_keys($splits)).").";
    }
}
foreach(['TRAIN','VAL','TEST'] as $split){
    if($splitCounts[$split]===0){
        $problems[]="Split {$split} está vazio.";
    }
}

if($problems){
    http_response_code(422);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Exportação bloqueada por inconsistências:\n\n- ".implode("\n- ",array_values(array_unique($problems)));
    exit;
}

$tmp=tempnam(sys_get_temp_dir(),'hemacias_dataset_');
$zip=new ZipArchive();
if($zip->open($tmp,ZipArchive::OVERWRITE)!==true){
    http_response_code(500);exit('Não foi possível criar o ZIP.');
}

$countBySplit=['TRAIN'=>0,'VAL'=>0,'TEST'=>0];
foreach($images as $image){
    $baseDir=realpath((string)$config['app']['upload_dir']);
    $file=$baseDir?realpath($baseDir.DIRECTORY_SEPARATOR.$image['stored_name']):false;
    if(!$file || !is_file($file))continue;

    $split=strtolower($image['split_set']);
    $ext=strtolower(pathinfo($image['original_name'],PATHINFO_EXTENSION) ?: pathinfo($file,PATHINFO_EXTENSION));
    $safeBase='image_'.$image['id'];
    $zip->addFile($file,"images/$split/$safeBase.$ext");

    $ann=db()->prepare(
        "SELECT class_code,polygon_json FROM image_annotations
         WHERE image_id=? AND review_status='APROVADA' ORDER BY id"
    );
    $ann->execute([(int)$image['id']]);
    $lines=[];
    $w=max(1,(int)$image['width_px']);$h=max(1,(int)$image['height_px']);
    foreach($ann->fetchAll() as $a){
        $code=(string)$a['class_code'];
        if(!isset($classes[$code]))continue;
        $points=json_decode((string)$a['polygon_json'],true)?:[];
        if(count($points)<3)continue;
        $parts=[(string)$classes[$code]['id']];
        foreach($points as $p){
            $parts[]=number_format(max(0,min(1,(float)$p[0]/$w)),6,'.','');
            $parts[]=number_format(max(0,min(1,(float)$p[1]/$h)),6,'.','');
        }
        $lines[]=implode(' ',$parts);
    }
    $zip->addFromString("labels/$split/$safeBase.txt",implode("\n",$lines).($lines?"\n":""));
    $countBySplit[$image['split_set']]++;
}

$yaml="path: .\ntrain: images/train\nval: images/val\ntest: images/test\nnames:\n";
foreach($classes as $meta){$yaml.="  {$meta['id']}: {$meta['name']}\n";}
$zip->addFromString('dataset.yaml',$yaml);
$latestRun=db()->query(
    "SELECT id,group_mode,train_ratio,val_ratio,test_ratio,seed_value,eligible_images,group_count,
            train_images,val_images,test_images,created_at
     FROM dataset_split_runs ORDER BY created_at DESC,id DESC LIMIT 1"
)->fetch()?:null;

$zip->addFromString('manifest.json',json_encode([
    'generated_at'=>date(DATE_ATOM),
    'counts'=>$countBySplit,
    'classes'=>$classes,
    'split_provenance'=>$latestRun,
    'leakage_policy'=>'patient_and_sample_must_not_cross_splits',
],JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT));
$zip->close();

header('Content-Type: application/zip');
header('Content-Disposition: attachment; filename="hemacias_dataset_'.date('Ymd_His').'.zip"');
header('Content-Length: '.filesize($tmp));
readfile($tmp);
unlink($tmp);
