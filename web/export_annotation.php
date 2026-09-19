<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
require_login();

$imageId=(int)($_GET['image_id']??0);
$format=strtolower((string)($_GET['format']??'labelme'));

$st=db()->prepare('SELECT * FROM sample_images WHERE id=?');
$st->execute([$imageId]);
$image=$st->fetch();
if(!$image){http_response_code(404);exit('Imagem não encontrada.');}

$st=db()->prepare(
    'SELECT class_code,class_name,polygon_json FROM image_annotations
     WHERE image_id=? AND review_status=\'APROVADA\' ORDER BY id'
);
$st->execute([$imageId]);
$annotations=$st->fetchAll();

$width=max(1,(int)$image['width_px']);
$height=max(1,(int)$image['height_px']);
$base=pathinfo($image['original_name'],PATHINFO_FILENAME);

if($format==='yolo'){
    $classMap=['hemacia'=>0,'leucocito'=>1,'plaqueta'=>2,'artefato'=>3,'outro'=>4];
    $lines=[];
    foreach($annotations as $ann){
        $code=(string)$ann['class_code'];
        if(!array_key_exists($code,$classMap))continue;
        $points=json_decode((string)$ann['polygon_json'],true)?:[];
        if(count($points)<3)continue;
        $parts=[(string)$classMap[$code]];
        foreach($points as $p){
            $parts[]=number_format(max(0,min(1,(float)$p[0]/$width)),6,'.','');
            $parts[]=number_format(max(0,min(1,(float)$p[1]/$height)),6,'.','');
        }
        $lines[]=implode(' ',$parts);
    }
    header('Content-Type: text/plain; charset=utf-8');
    header('Content-Disposition: attachment; filename="'.$base.'.txt"');
    echo implode("\n",$lines).($lines?"\n":"");
    exit;
}

$shapes=[];
foreach($annotations as $ann){
    $points=json_decode((string)$ann['polygon_json'],true)?:[];
    if(count($points)<3)continue;
    $shapes[]=[
        'label'=>$ann['class_code'],
        'points'=>$points,
        'group_id'=>null,
        'description'=>'',
        'shape_type'=>'polygon',
        'flags'=>new stdClass(),
        'mask'=>null,
    ];
}
$payload=[
    'version'=>'5.5.0',
    'flags'=>new stdClass(),
    'shapes'=>$shapes,
    'imagePath'=>$image['original_name'],
    'imageData'=>null,
    'imageHeight'=>$height,
    'imageWidth'=>$width,
];
header('Content-Type: application/json; charset=utf-8');
header('Content-Disposition: attachment; filename="'.$base.'.json"');
echo json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
