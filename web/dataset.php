<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
$user=require_login();

$state=(string)($_GET['state']??'');
$split=(string)($_GET['split']??'');
$q=trim((string)($_GET['q']??''));
$error='';

if($_SERVER['REQUEST_METHOD']==='POST'){
    if(($user['role']??'')==='LEITURA'){
        http_response_code(403); exit('Perfil somente leitura.');
    }
    csrf_check();
    try{
        $action=(string)($_POST['action']??'');
        if($action==='update_item'){
            $imageId=(int)$_POST['image_id'];
            $reviewState=(string)$_POST['review_state'];
            $splitSet=(string)$_POST['split_set'];
            $included=isset($_POST['included'])?1:0;
            if(!in_array($reviewState,['PENDENTE','REVISADA','APROVADA','REJEITADA'],true)) throw new RuntimeException('Estado inválido.');
            if(!in_array($splitSet,['NAO_DEFINIDO','TRAIN','VAL','TEST'],true)) throw new RuntimeException('Split inválido.');
            $pdo=db();
            $pdo->prepare(
                'INSERT INTO dataset_items(image_id,review_state,split_set,included,reviewed_by,reviewed_at,approved_by,approved_at)
                 VALUES(?,?,?,?,?,NOW(),?,?,?)
                 ON DUPLICATE KEY UPDATE
                   review_state=VALUES(review_state),split_set=VALUES(split_set),included=VALUES(included),
                   reviewed_by=VALUES(reviewed_by),reviewed_at=VALUES(reviewed_at),
                   approved_by=VALUES(approved_by),approved_at=VALUES(approved_at)'
            )->execute([
                $imageId,$reviewState,$splitSet,$included,(int)$user['id'],
                $reviewState==='APROVADA'?(int)$user['id']:null,
                $reviewState==='APROVADA'?date('Y-m-d H:i:s'):null
            ]);
            audit('DATASET_ITEM_UPDATE','sample_image',$imageId,['state'=>$reviewState,'split'=>$splitSet,'included'=>$included]);
            header('Location: dataset.php?'.http_build_query(['state'=>$state,'split'=>$split,'q'=>$q]));
            exit;
        }
        if($action==='bulk_split'){
            $target=(string)$_POST['target_split'];
            $ids=array_values(array_filter(array_map('intval',$_POST['ids']??[])));
            if(!in_array($target,['TRAIN','VAL','TEST','NAO_DEFINIDO'],true)) throw new RuntimeException('Split inválido.');
            if($ids){
                $placeholders=implode(',',array_fill(0,count($ids),'?'));
                $params=array_merge([$target],$ids);
                db()->prepare("UPDATE dataset_items SET split_set=? WHERE image_id IN ($placeholders)")->execute($params);
            }
            header('Location: dataset.php');
            exit;
        }

        if($action==='auto_split'){
            $groupMode=(string)($_POST['group_mode']??'SAMPLE');
            $trainRatio=(float)($_POST['train_ratio']??0.70);
            $valRatio=(float)($_POST['val_ratio']??0.15);
            $testRatio=(float)($_POST['test_ratio']??0.15);
            $seed=trim((string)($_POST['seed_value']??'hemacias-v1'));

            if(!in_array($groupMode,['SAMPLE','PATIENT'],true)) throw new RuntimeException('Modo de agrupamento inválido.');
            if($seed==='') throw new RuntimeException('Seed obrigatório.');
            foreach([$trainRatio,$valRatio,$testRatio] as $ratio){
                if($ratio<0 || $ratio>1) throw new RuntimeException('As proporções devem estar entre 0 e 1.');
            }
            $sum=$trainRatio+$valRatio+$testRatio;
            if(abs($sum-1.0)>0.0001) throw new RuntimeException('TRAIN + VAL + TEST deve somar 1,0.');

            $groupExpr=$groupMode==='PATIENT'?'p.id':'s.id';
            $st=db()->query(
                "SELECT i.id image_id, s.id sample_id, p.id patient_id, $groupExpr group_id
                 FROM dataset_items d
                 JOIN sample_images i ON i.id=d.image_id
                 JOIN samples s ON s.id=i.sample_id
                 JOIN patients p ON p.id=s.patient_id
                 WHERE d.review_state='APROVADA' AND d.included=1
                 ORDER BY i.id"
            );
            $rows=$st->fetchAll();
            if(!$rows) throw new RuntimeException('Não há imagens aprovadas e incluídas para dividir.');

            $groups=[];
            foreach($rows as $row){
                $gid=(string)$row['group_id'];
                $groups[$gid]??=[];
                $groups[$gid][]=(int)$row['image_id'];
            }

            $groupList=[];
            foreach($groups as $gid=>$imageIds){
                $groupList[]=[
                    'id'=>$gid,
                    'images'=>$imageIds,
                    'size'=>count($imageIds),
                    'order'=>hash('sha256',$seed.'|'.$groupMode.'|'.$gid),
                ];
            }

            usort($groupList,function($a,$b){
                if($a['size']===$b['size']) return strcmp($a['order'],$b['order']);
                return $b['size']<=>$a['size'];
            });

            $total=count($rows);
            $targets=[
                'TRAIN'=>$total*$trainRatio,
                'VAL'=>$total*$valRatio,
                'TEST'=>$total*$testRatio,
            ];
            $counts=['TRAIN'=>0,'VAL'=>0,'TEST'=>0];
            $assignments=[];

            foreach($groupList as $group){
                $bestSplit=null;
                $bestScore=null;
                foreach(['TRAIN','VAL','TEST'] as $candidate){
                    $temp=$counts;
                    $temp[$candidate]+=$group['size'];
                    $score=0.0;
                    foreach(['TRAIN','VAL','TEST'] as $splitName){
                        $den=max(1.0,$targets[$splitName]);
                        $score+=pow(($temp[$splitName]-$targets[$splitName])/$den,2);
                    }
                    if($bestScore===null || $score<$bestScore){
                        $bestScore=$score;
                        $bestSplit=$candidate;
                    }
                }
                $counts[$bestSplit]+=$group['size'];
                $assignments[]=['group_id'=>$group['id'],'split'=>$bestSplit,'image_ids'=>$group['images']];
            }

            $pdo=db();$pdo->beginTransaction();
            try{
                $pdo->exec("UPDATE dataset_items SET split_set='NAO_DEFINIDO' WHERE review_state='APROVADA' AND included=1");
                $upd=$pdo->prepare('UPDATE dataset_items SET split_set=? WHERE image_id=?');
                foreach($assignments as $assignment){
                    foreach($assignment['image_ids'] as $imageId){
                        $upd->execute([$assignment['split'],$imageId]);
                    }
                }
                $details=[
                    'targets'=>$targets,
                    'counts'=>$counts,
                    'assignments'=>$assignments,
                ];
                $pdo->prepare(
                    'INSERT INTO dataset_split_runs(
                        group_mode,train_ratio,val_ratio,test_ratio,seed_value,
                        eligible_images,group_count,train_images,val_images,test_images,
                        created_by,details_json
                     ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)'
                )->execute([
                    $groupMode,$trainRatio,$valRatio,$testRatio,$seed,
                    $total,count($groupList),$counts['TRAIN'],$counts['VAL'],$counts['TEST'],
                    (int)$user['id'],json_encode($details,JSON_UNESCAPED_UNICODE)
                ]);
                $pdo->commit();
            }catch(Throwable $e){
                if($pdo->inTransaction())$pdo->rollBack();
                throw $e;
            }

            audit('DATASET_AUTO_SPLIT','dataset_split_run',(int)$pdo->lastInsertId(),[
                'group_mode'=>$groupMode,'seed'=>$seed,'counts'=>$counts
            ]);
            header('Location: dataset.php');
            exit;
        }
    }catch(Throwable $e){$error=$e->getMessage();}
}

db()->exec(
    "INSERT INTO dataset_items(image_id)
     SELECT i.id FROM sample_images i
     LEFT JOIN dataset_items d ON d.image_id=i.id
     WHERE d.id IS NULL"
);

$where=[];$params=[];
if($state!==''){ $where[]='d.review_state=?'; $params[]=$state; }
if($split!==''){ $where[]='d.split_set=?'; $params[]=$split; }
if($q!==''){
    $where[]='(p.name LIKE ? OR s.sample_code LIKE ? OR i.original_name LIKE ?)';
    $like='%'.$q.'%'; $params[]=$like;$params[]=$like;$params[]=$like;
}
$sql='SELECT i.id image_id,i.original_name,i.scale_label,i.created_at,s.sample_code,p.name patient_name,
             d.review_state,d.split_set,d.included,
             COUNT(a.id) annotation_count,
             SUM(CASE WHEN a.review_status=\'APROVADA\' THEN 1 ELSE 0 END) approved_annotations
      FROM sample_images i
      JOIN samples s ON s.id=i.sample_id
      JOIN patients p ON p.id=s.patient_id
      JOIN dataset_items d ON d.image_id=i.id
      LEFT JOIN image_annotations a ON a.image_id=i.id
      '.($where?'WHERE '.implode(' AND ',$where):'').'
      GROUP BY i.id
      ORDER BY i.created_at DESC';
$st=db()->prepare($sql);$st->execute($params);$items=$st->fetchAll();

$metrics=db()->query(
    "SELECT
      COUNT(*) total,
      SUM(review_state='PENDENTE') pending_count,
      SUM(review_state='REVISADA') reviewed_count,
      SUM(review_state='APROVADA') approved_count,
      SUM(review_state='REJEITADA') rejected_count,
      SUM(split_set='TRAIN' AND included=1 AND review_state='APROVADA') train_count,
      SUM(split_set='VAL' AND included=1 AND review_state='APROVADA') val_count,
      SUM(split_set='TEST' AND included=1 AND review_state='APROVADA') test_count
     FROM dataset_items"
)->fetch();

$splitHistory=db()->query(
    "SELECT r.*,u.name created_by_name
     FROM dataset_split_runs r
     LEFT JOIN users u ON u.id=r.created_by
     ORDER BY r.created_at DESC
     LIMIT 10"
)->fetchAll();

$classStats=db()->query(
    "SELECT a.class_code,a.class_name,COUNT(*) quantity,COUNT(DISTINCT a.image_id) images
     FROM image_annotations a
     JOIN dataset_items d ON d.image_id=a.image_id
     WHERE a.review_status='APROVADA' AND d.review_state='APROVADA' AND d.included=1
     GROUP BY a.class_code,a.class_name
     ORDER BY quantity DESC"
)->fetchAll();
?><!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dataset - Hemácias</title><link rel="stylesheet" href="assets/style.css"></head><body>
<header><strong>Hemácias · Dataset</strong><nav><a href="index.php">Dashboard</a><a href="index.php?page=patients">Pacientes</a><a href="dataset.php">Dataset</a><a href="index.php?page=logout">Sair</a></nav></header>
<main class="container">
<h1>Gerenciador de dataset</h1>
<?php if($error):?><div class="error"><?=h($error)?></div><?php endif;?>
<div class="grid">
<div class="card"><div class="metric"><?=(int)$metrics['pending_count']?></div>Pendentes</div>
<div class="card"><div class="metric"><?=(int)$metrics['reviewed_count']?></div>Revisadas</div>
<div class="card"><div class="metric"><?=(int)$metrics['approved_count']?></div>Aprovadas</div>
<div class="card"><div class="metric"><?=(int)$metrics['train_count']?></div>Train</div>
<div class="card"><div class="metric"><?=(int)$metrics['val_count']?></div>Val</div>
<div class="card"><div class="metric"><?=(int)$metrics['test_count']?></div>Test</div>
</div>

<div class="card">
<form method="get" class="inline">
<label>Estado<select name="state"><option value="">Todos</option><?php foreach(['PENDENTE','REVISADA','APROVADA','REJEITADA'] as $v):?><option <?=$state===$v?'selected':''?>><?=$v?></option><?php endforeach;?></select></label>
<label>Split<select name="split"><option value="">Todos</option><?php foreach(['NAO_DEFINIDO','TRAIN','VAL','TEST'] as $v):?><option <?=$split===$v?'selected':''?>><?=$v?></option><?php endforeach;?></select></label>
<label>Pesquisa<input name="q" value="<?=h($q)?>" placeholder="Paciente, amostra ou arquivo"></label>
<div><button>Filtrar</button></div>
</form>
</div>

<div class="grid">
<div class="card">
<strong>Exportação:</strong>
<a class="button" href="export_dataset.php">Baixar dataset YOLO (.zip)</a>
<small class="muted">Somente imagens incluídas, aprovadas e com split TRAIN/VAL/TEST.</small>
</div>

<div class="card">
<h2>Divisão automática</h2>
<form method="post">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
<input type="hidden" name="action" value="auto_split">
<label>Agrupar por
<select name="group_mode">
<option value="SAMPLE">Amostra (recomendado)</option>
<option value="PATIENT">Paciente (mais rigoroso)</option>
</select></label>
<div class="inline">
<label>Train<input type="number" name="train_ratio" min="0" max="1" step="0.01" value="0.70" required></label>
<label>Val<input type="number" name="val_ratio" min="0" max="1" step="0.01" value="0.15" required></label>
<label>Test<input type="number" name="test_ratio" min="0" max="1" step="0.01" value="0.15" required></label>
</div>
<label>Seed<input name="seed_value" value="hemacias-v1" required></label>
<button>Calcular TRAIN / VAL / TEST</button>
<p><small class="muted">A divisão é aplicada somente às imagens APROVADAS e incluídas. Imagens do mesmo grupo nunca são separadas.</small></p>
</form>
</div>
</div>

<h2>Últimas divisões automáticas</h2>
<table><tr><th>Data</th><th>Agrupamento</th><th>Proporção</th><th>Resultado</th><th>Seed</th><th>Usuário</th></tr>
<?php foreach($splitHistory as $run):?>
<tr>
<td><?=h($run['created_at'])?></td>
<td><?=h($run['group_mode'])?></td>
<td><?=number_format((float)$run['train_ratio']*100,0)?> / <?=number_format((float)$run['val_ratio']*100,0)?> / <?=number_format((float)$run['test_ratio']*100,0)?>%</td>
<td><?=$run['train_images']?> / <?=$run['val_images']?> / <?=$run['test_images']?></td>
<td><?=h($run['seed_value'])?></td>
<td><?=h($run['created_by_name'])?></td>
</tr>
<?php endforeach;?></table>

<h2>Classes aprovadas</h2>
<table><tr><th>Classe</th><th>Objetos</th><th>Imagens</th></tr>
<?php foreach($classStats as $cs):?><tr><td><?=h($cs['class_name'])?> <small class="muted">(<?=h($cs['class_code'])?>)</small></td><td><?=$cs['quantity']?></td><td><?=$cs['images']?></td></tr><?php endforeach;?></table>

<h2>Imagens</h2>
<form method="post">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
<input type="hidden" name="action" value="bulk_split">
<div class="inline card"><label>Aplicar split aos selecionados<select name="target_split"><option>TRAIN</option><option>VAL</option><option>TEST</option><option>NAO_DEFINIDO</option></select></label><div><button>Aplicar</button></div></div>
<table><tr><th></th><th>Imagem</th><th>Paciente / amostra</th><th>Anotações</th><th>Estado</th><th>Split</th><th>Incluída</th><th>Ações</th></tr>
<?php foreach($items as $item):?>
<tr>
<td><input type="checkbox" name="ids[]" value="<?=$item['image_id']?>"></td>
<td><a href="image.php?id=<?=$item['image_id']?>" target="_blank"><?=h($item['original_name'])?></a><br><small class="muted"><?=h($item['scale_label'])?></small></td>
<td><?=h($item['patient_name'])?><br><small class="muted"><?=h($item['sample_code'])?></small></td>
<td><?=(int)$item['annotation_count']?> / <?=(int)$item['approved_annotations']?> aprovadas</td>
<td><?=h($item['review_state'])?></td><td><?=h($item['split_set'])?></td><td><?=$item['included']?'Sim':'Não'?></td>
<td><a class="button" href="annotation.php?image_id=<?=$item['image_id']?>">Revisar</a>
<button type="button" onclick="document.getElementById('edit<?=$item['image_id']?>').showModal()">Estado</button></td>
</tr>
<?php endforeach;?></table>
</form>

<?php foreach($items as $item):?>
<dialog id="edit<?=$item['image_id']?>"><form method="post" class="card" style="min-width:320px">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
<input type="hidden" name="action" value="update_item">
<input type="hidden" name="image_id" value="<?=$item['image_id']?>">
<h3><?=h($item['original_name'])?></h3>
<label>Estado<select name="review_state"><?php foreach(['PENDENTE','REVISADA','APROVADA','REJEITADA'] as $v):?><option <?=$item['review_state']===$v?'selected':''?>><?=$v?></option><?php endforeach;?></select></label>
<label>Split<select name="split_set"><?php foreach(['NAO_DEFINIDO','TRAIN','VAL','TEST'] as $v):?><option <?=$item['split_set']===$v?'selected':''?>><?=$v?></option><?php endforeach;?></select></label>
<label><input type="checkbox" name="included" <?=$item['included']?'checked':''?>> Incluir no dataset</label>
<button>Salvar</button> <button type="button" onclick="this.closest('dialog').close()">Cancelar</button>
</form></dialog>
<?php endforeach;?>
</main></body></html>
