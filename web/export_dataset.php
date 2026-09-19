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
$zip->addFromString('manifest.json',json_encode([
    'generated_at'=>date(DATE_ATOM),
    'counts'=>$countBySplit,
    'classes'=>$classes,
],JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT));
$zip->close();

header('Content-Type: application/zip');
header('Content-Disposition: attachment; filename="hemacias_dataset_'.date('Ymd_His').'.zip"');
header('Content-Length: '.filesize($tmp));
readfile($tmp);
unlink($tmp);
