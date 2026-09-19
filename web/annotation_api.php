<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

$user = require_login();
header('Content-Type: application/json; charset=utf-8');

function ann_json(array $payload, int $status = 200): never {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if (($user['role'] ?? '') === 'LEITURA' && $_SERVER['REQUEST_METHOD'] !== 'GET') {
    ann_json(['ok'=>false,'error'=>'Perfil somente leitura.'],403);
}

$imageId=(int)($_GET['image_id']??$_POST['image_id']??0);
if($imageId<1) ann_json(['ok'=>false,'error'=>'image_id obrigatório'],422);

$st=db()->prepare('SELECT id,width_px,height_px FROM sample_images WHERE id=?');
$st->execute([$imageId]);
$image=$st->fetch();
if(!$image) ann_json(['ok'=>false,'error'=>'Imagem não encontrada'],404);

if($_SERVER['REQUEST_METHOD']==='GET'){
    $st=db()->prepare(
        'SELECT ia.id,ia.class_code,ia.class_name,ia.polygon_json,ia.source,ia.review_status,ia.notes,
                ia.created_at,ia.updated_at,u.name created_by_name
         FROM image_annotations ia
         LEFT JOIN users u ON u.id=ia.created_by
         WHERE ia.image_id=?
         ORDER BY ia.id'
    );
    $st->execute([$imageId]);
    $items=[];
    foreach($st->fetchAll() as $row){
        $row['polygon']=json_decode((string)$row['polygon_json'],true)?:[];
        unset($row['polygon_json']);
        $items[]=$row;
    }
    ann_json(['ok'=>true,'image'=>$image,'annotations'=>$items]);
}

csrf_check();
$action=(string)($_POST['action']??'');

if($action==='save_all'){
    $raw=(string)($_POST['annotations']??'[]');
    $items=json_decode($raw,true);
    if(!is_array($items)) ann_json(['ok'=>false,'error'=>'annotations inválido'],422);

    $width=max(1,(int)$image['width_px']);
    $height=max(1,(int)$image['height_px']);
    $clean=[];

    foreach($items as $idx=>$item){
        $classCode=trim((string)($item['class_code']??'hemacia'));
        $className=trim((string)($item['class_name']??'Hemácia'));
        $polygon=$item['polygon']??null;
        if($classCode==='' || $className==='' || !is_array($polygon) || count($polygon)<3){
            ann_json(['ok'=>false,'error'=>"Anotação {$idx} inválida."],422);
        }
        $points=[];
        foreach($polygon as $point){
            if(!is_array($point) || count($point)<2) ann_json(['ok'=>false,'error'=>"Ponto inválido na anotação {$idx}."],422);
            $x=(float)$point[0]; $y=(float)$point[1];
            if(!is_finite($x)||!is_finite($y)||$x<0||$x>$width||$y<0||$y>$height){
                ann_json(['ok'=>false,'error'=>"Ponto fora dos limites na anotação {$idx}."],422);
            }
            $points[]=[$x,$y];
        }
        $clean[]=[
            'class_code'=>$classCode,
            'class_name'=>$className,
            'polygon'=>$points,
            'review_status'=>in_array(($item['review_status']??'APROVADA'),['PENDENTE','APROVADA','REJEITADA'],true)?$item['review_status']:'APROVADA',
            'notes'=>trim((string)($item['notes']??''))?:null,
        ];
    }

    $pdo=db(); $pdo->beginTransaction();
    try{
        $pdo->prepare('DELETE FROM image_annotations WHERE image_id=? AND source=\'MANUAL\'')->execute([$imageId]);
        $ins=$pdo->prepare(
            'INSERT INTO image_annotations(image_id,class_code,class_name,polygon_json,source,review_status,notes,created_by)
             VALUES(?,?,?,?,\'MANUAL\',?,?,?)'
        );
        foreach($clean as $item){
            $ins->execute([
                $imageId,$item['class_code'],$item['class_name'],
                json_encode($item['polygon'],JSON_UNESCAPED_UNICODE),
                $item['review_status'],$item['notes'],(int)$user['id']
            ]);
        }
        $rev=$pdo->prepare(
            'INSERT INTO annotation_revisions(image_id,user_id,action_type,details_json) VALUES(?,?,?,?)'
        );
        $rev->execute([
            $imageId,(int)$user['id'],'SAVE_ALL',
            json_encode(['count'=>count($clean)],JSON_UNESCAPED_UNICODE)
        ]);
        $pdo->commit();
        audit('ANNOTATION_SAVE','sample_image',$imageId,['count'=>count($clean)]);
        ann_json(['ok'=>true,'saved'=>count($clean)]);
    }catch(Throwable $e){
        if($pdo->inTransaction())$pdo->rollBack();
        ann_json(['ok'=>false,'error'=>$e->getMessage()],500);
    }
}

ann_json(['ok'=>false,'error'=>'Ação não encontrada'],404);
