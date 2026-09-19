<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
$user=require_login();
require_admin($user);
$error='';

if($_SERVER['REQUEST_METHOD']==='POST'){
    csrf_check();
    try{
        $action=(string)($_POST['action']??'');
        if($action==='save_model'){
            $id=(int)($_POST['id']??0);
            $code=strtolower(trim((string)($_POST['code']??'')));
            $name=trim((string)($_POST['name']??''));
            $version=trim((string)($_POST['version']??''));
            $filePath=trim((string)($_POST['file_path']??''));
            $status=(string)($_POST['status']??'TREINO');
            $type=(string)($_POST['model_type']??'YOLO_SEG');
            if(!preg_match('/^[a-z0-9_\-]+$/',$code)) throw new RuntimeException('Código inválido.');
            if($name===''||$version===''||$filePath==='') throw new RuntimeException('Nome, versão e caminho do modelo são obrigatórios.');
            if(!in_array($status,['TREINO','VALIDACAO','APROVADO','INATIVO'],true)) throw new RuntimeException('Status inválido.');
            if(!in_array($type,['YOLO_SEG','YOLO_DETECT','OUTRO'],true)) throw new RuntimeException('Tipo inválido.');
            $sha=strtolower(trim((string)($_POST['sha256']??'')));
            if($sha!==''&&!preg_match('/^[a-f0-9]{64}$/',$sha)) throw new RuntimeException('SHA-256 inválido.');

            $classes=array_values(array_filter(array_map('trim',explode(',',(string)($_POST['classes']??'')))));
            $approvedBy=$status==='APROVADO'?(int)$user['id']:null;
            $approvedAt=$status==='APROVADO'?date('Y-m-d H:i:s'):null;
            $vals=[
                $code,$name,$version,$type,$status,$filePath,$sha?:null,
                trim((string)($_POST['dataset_ref']??''))?:null,
                $_POST['imgsz']===''?null:(int)$_POST['imgsz'],
                $_POST['epochs']===''?null:(int)$_POST['epochs'],
                json_encode($classes,JSON_UNESCAPED_UNICODE),
                $_POST['trained_at']?str_replace('T',' ',(string)$_POST['trained_at']).':00':null,
                trim((string)($_POST['notes']??''))?:null,
                $approvedBy,$approvedAt
            ];
            if($id){
                $st=db()->prepare('UPDATE ai_models SET code=?,name=?,version=?,model_type=?,status=?,file_path=?,sha256=?,dataset_ref=?,imgsz=?,epochs=?,classes_json=?,trained_at=?,notes=?,approved_by=?,approved_at=? WHERE id=?');
                $st->execute([...$vals,$id]);
                audit('UPDATE','ai_model',$id);
            }else{
                $st=db()->prepare('INSERT INTO ai_models(code,name,version,model_type,status,file_path,sha256,dataset_ref,imgsz,epochs,classes_json,trained_at,notes,approved_by,approved_at,created_by) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
                $st->execute([...$vals,(int)$user['id']]);
                $id=(int)db()->lastInsertId();
                audit('CREATE','ai_model',$id);
            }
            header('Location: models.php');exit;
        }

        if($action==='save_metric'){
            $modelId=(int)$_POST['model_id'];
            $itemTypeId=(int)($_POST['item_type_id']??0);
            $scope=$itemTypeId>0?'CLASSE':'GERAL';
            $v=function(string $name){
                $raw=trim((string)($_POST[$name]??''));
                return $raw===''?null:(float)$raw;
            };
            $st=db()->prepare(
                'INSERT INTO ai_model_metrics(model_id,item_type_id,metric_scope,precision_value,recall_value,f1_value,map50_value,map5095_value,mae_value,bias_value,mape_value,sample_count,notes)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                 ON DUPLICATE KEY UPDATE precision_value=VALUES(precision_value),recall_value=VALUES(recall_value),f1_value=VALUES(f1_value),map50_value=VALUES(map50_value),map5095_value=VALUES(map5095_value),mae_value=VALUES(mae_value),bias_value=VALUES(bias_value),mape_value=VALUES(mape_value),sample_count=VALUES(sample_count),notes=VALUES(notes)'
            );
            $st->execute([
                $modelId,$itemTypeId?:null,$scope,$v('precision'),$v('recall'),$v('f1'),
                $v('map50'),$v('map5095'),$v('mae'),$v('bias'),$v('mape'),
                $_POST['sample_count']===''?null:(int)$_POST['sample_count'],
                trim((string)($_POST['notes']??''))?:null
            ]);
            audit('MODEL_METRIC','ai_model',$modelId,['item_type_id'=>$itemTypeId?:null]);
            header('Location: models.php');exit;
        }
    }catch(Throwable $e){$error=$e->getMessage();}
}

$models=db()->query(
    "SELECT m.*,uc.name created_by_name,ua.name approved_by_name
     FROM ai_models m
     LEFT JOIN users uc ON uc.id=m.created_by
     LEFT JOIN users ua ON ua.id=m.approved_by
     ORDER BY FIELD(m.status,'APROVADO','VALIDACAO','TREINO','INATIVO'),m.name,m.version"
)->fetchAll();
$items=db()->query('SELECT id,code,name FROM count_item_types WHERE active=1 ORDER BY sort_order,name')->fetchAll();
$metrics=[];
foreach(db()->query(
    "SELECT mm.*,cit.name item_name,cit.code item_code
     FROM ai_model_metrics mm
     LEFT JOIN count_item_types cit ON cit.id=mm.item_type_id
     ORDER BY mm.model_id,mm.metric_scope,cit.sort_order,cit.name"
)->fetchAll() as $m){$metrics[(int)$m['model_id']][]=$m;}
?><!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Modelos de IA - Hemácias</title><link rel="stylesheet" href="assets/style.css"></head><body>
<header><strong>Hemácias · Modelos de IA</strong><nav><a href="index.php">Dashboard</a><a href="resources.php">Recursos</a><a href="models.php">Modelos</a><a href="dataset.php">Dataset</a><a href="index.php?page=logout">Sair</a></nav></header>
<main class="container"><h1>Gestão de modelos de IA</h1>
<?php if($error):?><div class="error"><?=h($error)?></div><?php endif;?>

<section class="card"><h2>Novo modelo</h2>
<form method="post"><input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_model">
<div class="grid">
<label>Código<input name="code" required placeholder="blood_seg"></label>
<label>Nome<input name="name" required placeholder="Blood Seg"></label>
<label>Versão<input name="version" required placeholder="v1"></label>
<label>Tipo<select name="model_type"><option>YOLO_SEG</option><option>YOLO_DETECT</option><option>OUTRO</option></select></label>
<label>Status<select name="status"><option>TREINO</option><option>VALIDACAO</option><option>APROVADO</option><option>INATIVO</option></select></label>
<label>Caminho do arquivo<input name="file_path" required placeholder="models/blood-seg-v1.pt"></label>
<label>SHA-256<input name="sha256" maxlength="64"></label>
<label>Dataset<input name="dataset_ref" placeholder="dataset-2026-09-v1"></label>
<label>imgsz<input type="number" name="imgsz" value="1024"></label>
<label>epochs<input type="number" name="epochs" value="100"></label>
<label>Treinado em<input type="datetime-local" name="trained_at"></label>
<label>Classes (vírgula)<input name="classes" placeholder="hemacia,leucocito,plaqueta,artefato"></label>
</div>
<label>Observações<textarea name="notes"></textarea></label><button>Cadastrar modelo</button></form></section>

<h2>Modelos cadastrados</h2>
<?php foreach($models as $m):$classes=json_decode((string)$m['classes_json'],true)?:[];?>
<section class="card">
<h3><?=h($m['name'])?> · <?=h($m['version'])?> <small class="muted"><?=h($m['status'])?></small></h3>
<p><b>Código:</b> <?=h($m['code'])?> · <b>Tipo:</b> <?=h($m['model_type'])?> · <b>Arquivo:</b> <?=h($m['file_path'])?></p>
<p><b>SHA-256:</b> <?=h($m['sha256']?:'não informado')?> · <b>Dataset:</b> <?=h($m['dataset_ref'])?> · <b>imgsz:</b> <?=h((string)$m['imgsz'])?> · <b>epochs:</b> <?=h((string)$m['epochs'])?></p>
<p><b>Classes:</b> <?=h(implode(', ',$classes))?></p>
<button type="button" onclick="document.getElementById('model<?=$m['id']?>').showModal()">Editar modelo</button>
<button type="button" onclick="document.getElementById('metric<?=$m['id']?>').showModal()">Registrar métrica</button>

<?php if(!empty($metrics[(int)$m['id']])):?><table><tr><th>Escopo</th><th>Precision</th><th>Recall</th><th>F1</th><th>mAP50</th><th>mAP50-95</th><th>MAE</th><th>Viés</th><th>MAPE</th><th>N</th></tr>
<?php foreach($metrics[(int)$m['id']] as $mm):?><tr>
<td><?=h($mm['item_name']?:'Geral')?></td><td><?=h((string)$mm['precision_value'])?></td><td><?=h((string)$mm['recall_value'])?></td><td><?=h((string)$mm['f1_value'])?></td>
<td><?=h((string)$mm['map50_value'])?></td><td><?=h((string)$mm['map5095_value'])?></td><td><?=h((string)$mm['mae_value'])?></td><td><?=h((string)$mm['bias_value'])?></td><td><?=h((string)$mm['mape_value'])?></td><td><?=h((string)$mm['sample_count'])?></td>
</tr><?php endforeach;?></table><?php endif;?>
</section>

<dialog id="model<?=$m['id']?>"><form method="post" class="card" style="min-width:520px">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_model"><input type="hidden" name="id" value="<?=$m['id']?>">
<h3>Editar <?=h($m['name'])?></h3>
<label>Código<input name="code" value="<?=h($m['code'])?>" required></label><label>Nome<input name="name" value="<?=h($m['name'])?>" required></label>
<label>Versão<input name="version" value="<?=h($m['version'])?>" required></label>
<label>Tipo<select name="model_type"><?php foreach(['YOLO_SEG','YOLO_DETECT','OUTRO'] as $v):?><option <?=$m['model_type']===$v?'selected':''?>><?=$v?></option><?php endforeach;?></select></label>
<label>Status<select name="status"><?php foreach(['TREINO','VALIDACAO','APROVADO','INATIVO'] as $v):?><option <?=$m['status']===$v?'selected':''?>><?=$v?></option><?php endforeach;?></select></label>
<label>Caminho<input name="file_path" value="<?=h($m['file_path'])?>" required></label><label>SHA-256<input name="sha256" value="<?=h($m['sha256'])?>"></label>
<label>Dataset<input name="dataset_ref" value="<?=h($m['dataset_ref'])?>"></label><label>imgsz<input type="number" name="imgsz" value="<?=h((string)$m['imgsz'])?>"></label>
<label>epochs<input type="number" name="epochs" value="<?=h((string)$m['epochs'])?>"></label>
<label>Treinado em<input type="datetime-local" name="trained_at" value="<?=h($m['trained_at']?date('Y-m-d\TH:i',strtotime($m['trained_at'])):'')?>"></label>
<label>Classes<input name="classes" value="<?=h(implode(',',$classes))?>"></label><label>Observações<textarea name="notes"><?=h($m['notes'])?></textarea></label>
<button>Salvar</button> <button type="button" onclick="this.closest('dialog').close()">Cancelar</button></form></dialog>

<dialog id="metric<?=$m['id']?>"><form method="post" class="card" style="min-width:520px">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_metric"><input type="hidden" name="model_id" value="<?=$m['id']?>">
<h3>Métrica · <?=h($m['name'].' '.$m['version'])?></h3>
<label>Componente<select name="item_type_id"><option value="0">Geral</option><?php foreach($items as $it):?><option value="<?=$it['id']?>"><?=h($it['name'])?></option><?php endforeach;?></select></label>
<div class="grid">
<label>Precision<input type="number" step="0.000001" name="precision"></label><label>Recall<input type="number" step="0.000001" name="recall"></label>
<label>F1<input type="number" step="0.000001" name="f1"></label><label>mAP50<input type="number" step="0.000001" name="map50"></label>
<label>mAP50-95<input type="number" step="0.000001" name="map5095"></label><label>MAE<input type="number" step="0.000001" name="mae"></label>
<label>Viés<input type="number" step="0.000001" name="bias"></label><label>MAPE<input type="number" step="0.000001" name="mape"></label>
<label>N<input type="number" name="sample_count"></label>
</div><label>Observações<textarea name="notes"></textarea></label><button>Salvar métrica</button></form></dialog>
<?php endforeach;?>
</main></body></html>