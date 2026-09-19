<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
$user=require_login();

$sampleId=(int)($_GET['sample_id']??0);
$st=db()->prepare(
    'SELECT s.*,p.name patient_name,p.id patient_id
     FROM samples s JOIN patients p ON p.id=s.patient_id
     WHERE s.id=?'
);
$st->execute([$sampleId]);
$sample=$st->fetch();
if(!$sample){http_response_code(404);exit('Amostra não encontrada.');}

if($_SERVER['REQUEST_METHOD']==='POST'){
    if(($user['role']??'')==='LEITURA'){http_response_code(403);exit('Perfil somente leitura.');}
    csrf_check();
    $fieldId=(int)($_POST['field_id']??0);
    $status=(string)($_POST['status']??'REVISAR');
    $included=isset($_POST['included_in_summary'])?1:0;
    if(!in_array($status,['ACEITA','REJEITADA','REVISAR'],true)) exit('Status inválido.');
    $st=db()->prepare(
        'UPDATE microscopic_fields
         SET status=?,included_in_summary=?,quality_reason=?,reviewed_by=?,reviewed_at=NOW(),notes=?
         WHERE id=? AND sample_id=?'
    );
    $st->execute([
        $status,$included,trim((string)($_POST['quality_reason']??''))?:null,
        (int)$user['id'],trim((string)($_POST['notes']??''))?:null,$fieldId,$sampleId
    ]);
    audit('FIELD_REVIEW','microscopic_field',$fieldId,['status'=>$status,'included'=>$included]);
    header('Location: sample_analysis.php?sample_id='.$sampleId);
    exit;
}

$st=db()->prepare(
    'SELECT mf.*,c.id count_id,c.method,c.algorithm_version,c.image_quality,c.created_at count_created,
            i.id image_id,i.original_name,i.scale_label
     FROM microscopic_fields mf
     LEFT JOIN counts c ON c.field_id=mf.id
     LEFT JOIN sample_images i ON i.field_id=mf.id
     WHERE mf.sample_id=?
     ORDER BY mf.field_no'
);
$st->execute([$sampleId]);
$fields=$st->fetchAll();

$st=db()->prepare(
    "SELECT cc.component_code,cc.component_name,cc.quantity,mf.id field_id,mf.field_no
     FROM microscopic_fields mf
     JOIN counts c ON c.field_id=mf.id
     JOIN count_components cc ON cc.count_id=c.id
     WHERE mf.sample_id=? AND mf.status='ACEITA' AND mf.included_in_summary=1
     ORDER BY cc.component_code,mf.field_no"
);
$st->execute([$sampleId]);
$rows=$st->fetchAll();

$grouped=[];
foreach($rows as $row){
    $code=(string)$row['component_code'];
    $grouped[$code]['name']=$row['component_name'];
    $grouped[$code]['values'][]=(float)$row['quantity'];
}
function median(array $values): float {
    sort($values,SORT_NUMERIC); $n=count($values);
    if($n===0)return 0.0;
    $m=intdiv($n,2);
    return $n%2?$values[$m]:($values[$m-1]+$values[$m])/2;
}
function stddev(array $values): float {
    $n=count($values); if($n<2)return 0.0;
    $mean=array_sum($values)/$n; $sum=0.0;
    foreach($values as $v)$sum+=($v-$mean)**2;
    return sqrt($sum/($n-1));
}
$accepted=0;$rejected=0;$review=0;
foreach($fields as $f){
    if($f['status']==='ACEITA' && $f['included_in_summary'])$accepted++;
    elseif($f['status']==='REJEITADA' || !$f['included_in_summary'])$rejected++;
    else $review++;
}
?><!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Análise da amostra - Hemácias</title><link rel="stylesheet" href="assets/style.css"></head><body>
<header><strong>Hemácias · Análise da amostra</strong><nav>
<a href="index.php?page=sample&id=<?=$sampleId?>">Voltar à amostra</a>
<a href="dataset.php">Dataset</a><a href="index.php?page=logout">Sair</a></nav></header>
<main class="container">
<h1>Amostra <?=h($sample['sample_code'])?></h1>
<p>Paciente: <?=h($sample['patient_name'])?></p>

<div class="grid">
<div class="card"><div class="metric"><?=count($fields)?></div>Campos totais</div>
<div class="card"><div class="metric"><?=$accepted?></div>Campos válidos</div>
<div class="card"><div class="metric"><?=$rejected?></div>Campos rejeitados/excluídos</div>
<div class="card"><div class="metric"><?=$review?></div>Campos para revisar</div>
</div>

<h2>Resultado consolidado</h2>
<?php if(!$grouped):?>
<div class="card">Ainda não há campos ACEITOS e incluídos suficientes para consolidação.</div>
<?php else:?>
<table><tr><th>Componente</th><th>Campos</th><th>Média</th><th>Mediana</th><th>Mínimo</th><th>Máximo</th><th>Desvio padrão</th></tr>
<?php foreach($grouped as $code=>$g):
$v=$g['values'];$n=count($v);$avg=$n?array_sum($v)/$n:0;?>
<tr><td><?=h($g['name'])?></td><td><?=$n?></td><td><?=number_format($avg,2,',','.')?></td>
<td><?=number_format(median($v),2,',','.')?></td><td><?=number_format(min($v),2,',','.')?></td>
<td><?=number_format(max($v),2,',','.')?></td><td><?=number_format(stddev($v),2,',','.')?></td></tr>
<?php endforeach;?></table>
<?php endif;?>

<h2>Campos microscópicos</h2>
<table><tr><th>Campo</th><th>Imagem</th><th>Qualidade</th><th>Foco</th><th>Status</th><th>Incluído</th><th>Contagem</th><th>Ação</th></tr>
<?php foreach($fields as $f):?>
<tr>
<td>#<?=$f['field_no']?></td>
<td><?php if($f['image_id']):?><a href="image.php?id=<?=$f['image_id']?>" target="_blank"><?=h($f['original_name'])?></a><?php else:?>—<?php endif;?></td>
<td><?=h($f['image_quality']?:$f['quality_reason'])?></td>
<td><?=h((string)$f['focus_score'])?></td>
<td><?=h($f['status'])?></td>
<td><?=$f['included_in_summary']?'Sim':'Não'?></td>
<td><?php if($f['count_id']):?><a href="index.php?page=count&id=<?=$f['count_id']?>">#<?=$f['count_id']?></a><?php else:?>—<?php endif;?></td>
<td><button type="button" onclick="document.getElementById('field<?=$f['id']?>').showModal()">Revisar</button></td>
</tr>
<?php endforeach;?></table>

<?php foreach($fields as $f):?>
<dialog id="field<?=$f['id']?>"><form method="post" class="card" style="min-width:340px">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
<input type="hidden" name="field_id" value="<?=$f['id']?>">
<h3>Campo #<?=$f['field_no']?></h3>
<label>Status<select name="status">
<?php foreach(['ACEITA','REVISAR','REJEITADA'] as $v):?><option <?=$f['status']===$v?'selected':''?>><?=$v?></option><?php endforeach;?>
</select></label>
<label><input type="checkbox" name="included_in_summary" <?=$f['included_in_summary']?'checked':''?>> Incluir na consolidação</label>
<label>Motivo/qualidade<input name="quality_reason" value="<?=h($f['quality_reason'])?>"></label>
<label>Observações<textarea name="notes"><?=h($f['notes'])?></textarea></label>
<button>Salvar</button> <button type="button" onclick="this.closest('dialog').close()">Cancelar</button>
</form></dialog>
<?php endforeach;?>
</main></body></html>
