<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
$user=require_login();
require_admin($user);

$ids=array_values(array_unique(array_filter(array_map('intval',$_GET['models']??[]))));
$all=db()->query("SELECT id,code,name,version,status,dataset_ref,imgsz,epochs,trained_at FROM ai_models ORDER BY code,version")->fetchAll();

$selected=[];
$metrics=[];
if($ids){
    $ph=implode(',',array_fill(0,count($ids),'?'));
    $st=db()->prepare("SELECT id,code,name,version,status,dataset_ref,imgsz,epochs,trained_at,sha256,file_path FROM ai_models WHERE id IN ($ph) ORDER BY code,version");
    $st->execute($ids);$selected=$st->fetchAll();

    $st=db()->prepare(
        "SELECT mm.*,cit.code item_code,cit.name item_name,m.code model_code,m.version model_version
         FROM ai_model_metrics mm
         JOIN ai_models m ON m.id=mm.model_id
         LEFT JOIN count_item_types cit ON cit.id=mm.item_type_id
         WHERE mm.model_id IN ($ph)
         ORDER BY mm.metric_scope,cit.sort_order,cit.name,m.code,m.version"
    );
    $st->execute($ids);
    foreach($st->fetchAll() as $row){
        $key=$row['metric_scope']==='GERAL'?'__GERAL__':(string)$row['item_code'];
        $metrics[$key]['name']=$row['metric_scope']==='GERAL'?'Geral':$row['item_name'];
        $metrics[$key]['rows'][(int)$row['model_id']]=$row;
    }
}
?><!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Comparar modelos - Hemácias</title><link rel="stylesheet" href="assets/style.css"></head><body>
<header><strong>Hemácias · Comparação de modelos</strong><nav><a href="models.php">Modelos IA</a><a href="resources.php">Recursos</a><a href="index.php">Dashboard</a><a href="index.php?page=logout">Sair</a></nav></header>
<main class="container"><h1>Comparação entre versões</h1>
<form method="get" class="card">
<p>Selecione dois ou mais modelos para comparar métricas registradas.</p>
<div class="grid">
<?php foreach($all as $m):?><label><input type="checkbox" name="models[]" value="<?=$m['id']?>" <?=in_array((int)$m['id'],$ids,true)?'checked':''?>>
<?=h($m['name'].' '.$m['version'].' · '.$m['status'])?></label><?php endforeach;?>
</div><button>Comparar</button></form>

<?php if($selected):?>
<h2>Identificação</h2>
<table><tr><th>Modelo</th><th>Status</th><th>Dataset</th><th>imgsz</th><th>epochs</th><th>Treinado em</th></tr>
<?php foreach($selected as $m):?><tr><td><?=h($m['name'].' '.$m['version'])?></td><td><?=h($m['status'])?></td><td><?=h($m['dataset_ref'])?></td><td><?=h((string)$m['imgsz'])?></td><td><?=h((string)$m['epochs'])?></td><td><?=h($m['trained_at'])?></td></tr><?php endforeach;?></table>

<?php foreach($metrics as $metric):?>
<h2><?=h($metric['name'])?></h2>
<table><tr><th>Métrica</th><?php foreach($selected as $m):?><th><?=h($m['name'].' '.$m['version'])?></th><?php endforeach;?></tr>
<?php
$defs=[
 'precision_value'=>'Precision','recall_value'=>'Recall','f1_value'=>'F1',
 'map50_value'=>'mAP50','map5095_value'=>'mAP50-95','mae_value'=>'MAE',
 'bias_value'=>'Viés','mape_value'=>'MAPE','sample_count'=>'N'
];
foreach($defs as $key=>$label):?>
<tr><td><?=h($label)?></td><?php foreach($selected as $m):$r=$metric['rows'][(int)$m['id']]??null;?>
<td><?=h($r&&$r[$key]!==null?(string)$r[$key]:'—')?></td><?php endforeach;?></tr>
<?php endforeach;?></table>
<?php endforeach;?>
<p class="muted">A tabela apresenta os valores registrados para comparação técnica; a aprovação operacional continua sendo uma decisão explícita no cadastro do modelo.</p>
<?php endif;?>
</main></body></html>