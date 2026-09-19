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
        if($action==='save_item'){
            $id=(int)($_POST['id']??0);
            $code=strtolower(trim((string)($_POST['code']??'')));
            $name=trim((string)($_POST['name']??''));
            if(!preg_match('/^[a-z0-9_\-]+$/',$code)) throw new RuntimeException('Código inválido.');
            if($name==='') throw new RuntimeException('Nome obrigatório.');
            $values=[
                $code,$name,trim((string)$_POST['category'])?:'CELULA',
                preg_match('/^#[0-9a-fA-F]{6}$/',(string)$_POST['color_hex'])?(string)$_POST['color_hex']:'#00ff00',
                trim((string)$_POST['default_unit'])?:'objetos/campo',
                isset($_POST['ai_enabled'])?1:0,
                isset($_POST['annotation_enabled'])?1:0,
                isset($_POST['summary_enabled'])?1:0,
                max(0,min(1,(float)$_POST['confidence_threshold'])),
                $_POST['yolo_class_id']===''?null:(int)$_POST['yolo_class_id'],
                (int)$_POST['sort_order'],
                trim((string)$_POST['notes'])?:null,
                isset($_POST['active'])?1:0
            ];
            if($id){
                $st=db()->prepare('UPDATE count_item_types SET code=?,name=?,category=?,color_hex=?,default_unit=?,ai_enabled=?,annotation_enabled=?,summary_enabled=?,confidence_threshold=?,yolo_class_id=?,sort_order=?,notes=?,active=? WHERE id=?');
                $st->execute([...$values,$id]);
                audit('UPDATE','count_item_type',$id);
            }else{
                $st=db()->prepare('INSERT INTO count_item_types(code,name,category,color_hex,default_unit,ai_enabled,annotation_enabled,summary_enabled,confidence_threshold,yolo_class_id,sort_order,notes,active) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)');
                $st->execute($values);
                audit('CREATE','count_item_type',(int)db()->lastInsertId());
            }
            header('Location: resources.php');exit;
        }

        if($action==='save_protocol'){
            $id=(int)($_POST['id']??0);
            $code=strtolower(trim((string)($_POST['code']??'')));
            $name=trim((string)($_POST['name']??''));
            if(!preg_match('/^[a-z0-9_\-]+$/',$code)) throw new RuntimeException('Código inválido.');
            if($name==='') throw new RuntimeException('Nome obrigatório.');
            $vals=[
                $code,$name,isset($_POST['active'])?1:0,
                max(1,(int)$_POST['min_fields']),
                max(1,(int)$_POST['min_valid_fields']),
                trim((string)$_POST['default_scale_label'])?:null,
                $_POST['default_magnification']===''?null:(float)$_POST['default_magnification'],
                isset($_POST['require_quality'])?1:0,
                (int)($_POST['default_model_id']??0)?:null,
                trim((string)$_POST['notes'])?:null
            ];
            if($id){
                $st=db()->prepare('UPDATE count_protocols SET code=?,name=?,active=?,min_fields=?,min_valid_fields=?,default_scale_label=?,default_magnification=?,require_quality=?,default_model_id=?,notes=? WHERE id=?');
                $st->execute([...$vals,$id]); $protocolId=$id;
            }else{
                $st=db()->prepare('INSERT INTO count_protocols(code,name,active,min_fields,min_valid_fields,default_scale_label,default_magnification,require_quality,default_model_id,notes) VALUES(?,?,?,?,?,?,?,?,?,?)');
                $st->execute($vals);$protocolId=(int)db()->lastInsertId();
            }
            db()->prepare('DELETE FROM count_protocol_items WHERE protocol_id=?')->execute([$protocolId]);
            $ins=db()->prepare('INSERT INTO count_protocol_items(protocol_id,item_type_id,required_item,confidence_threshold,summary_enabled,sort_order) VALUES(?,?,?,?,?,?)');
            foreach($_POST['items']??[] as $itemId=>$data){
                $itemId=(int)$itemId;
                if(!isset($data['enabled'])) continue;
                $ins->execute([
                    $protocolId,$itemId,isset($data['required'])?1:0,
                    ($data['threshold']??'')===''?null:max(0,min(1,(float)$data['threshold'])),
                    isset($data['summary'])?1:0,(int)($data['sort_order']??100)
                ]);
            }
            audit($id?'UPDATE':'CREATE','count_protocol',$protocolId);
            header('Location: resources.php');exit;
        }
    }catch(Throwable $e){$error=$e->getMessage();}
}

$items=db()->query('SELECT * FROM count_item_types ORDER BY sort_order,name')->fetchAll();
$models=db()->query("SELECT id,name,version,status FROM ai_models WHERE status IN ('VALIDACAO','APROVADO') ORDER BY status='APROVADO' DESC,name,version")->fetchAll();
$protocols=db()->query('SELECT * FROM count_protocols ORDER BY active DESC,name')->fetchAll();
$protocolItems=[];
foreach(db()->query('SELECT cpi.*,cit.code,cit.name FROM count_protocol_items cpi JOIN count_item_types cit ON cit.id=cpi.item_type_id ORDER BY cpi.sort_order,cit.name')->fetchAll() as $pi){
    $protocolItems[(int)$pi['protocol_id']][]=$pi;
}
?><!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Recursos de contagem - Hemácias</title><link rel="stylesheet" href="assets/style.css"></head><body>
<header><strong>Hemácias · Recursos</strong><nav><a href="index.php">Dashboard</a><a href="resources.php">Recursos</a><a href="dataset.php">Dataset</a><a href="index.php?page=logout">Sair</a></nav></header>
<main class="container"><h1>Gestão dos recursos de contagem</h1>
<?php if($error):?><div class="error"><?=h($error)?></div><?php endif;?>

<div class="grid">
<section class="card"><h2>Novo componente</h2>
<form method="post"><input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_item">
<label>Código<input name="code" required placeholder="ex.: hemacia"></label><label>Nome<input name="name" required></label>
<label>Categoria<input name="category" value="CELULA"></label><label>Cor<input type="color" name="color_hex" value="#00ff00"></label>
<label>Unidade<input name="default_unit" value="objetos/campo"></label><label>Confiança mínima<input type="number" step="0.01" min="0" max="1" name="confidence_threshold" value="0.25"></label>
<label>ID da classe YOLO<input type="number" name="yolo_class_id"></label><label>Ordem<input type="number" name="sort_order" value="100"></label>
<label><input type="checkbox" name="active" checked> Ativo</label>
<label><input type="checkbox" name="ai_enabled" checked> IA</label>
<label><input type="checkbox" name="annotation_enabled" checked> Anotação</label>
<label><input type="checkbox" name="summary_enabled" checked> Consolidação</label>
<label>Observações<textarea name="notes"></textarea></label><button>Adicionar componente</button></form>
</section>

<section class="card"><h2>Novo protocolo</h2>
<form method="post"><input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_protocol">
<label>Código<input name="code" required></label><label>Nome<input name="name" required></label>
<div class="inline"><label>Campos mínimos<input type="number" min="1" name="min_fields" value="10"></label><label>Campos válidos mínimos<input type="number" min="1" name="min_valid_fields" value="8"></label></div>
<div class="inline"><label>Escala padrão<input name="default_scale_label" value="40x"></label><label>Magnificação<input type="number" step="0.001" name="default_magnification" value="40"></label></div>
<label><input type="checkbox" name="active" checked> Ativo</label><label><input type="checkbox" name="require_quality" checked> Exigir controle de qualidade</label>
<label>Modelo padrão<select name="default_model_id"><option value="0">Nenhum</option><?php foreach($models as $m):?><option value="<?=$m['id']?>"><?=h($m['name'].' '.$m['version'].' · '.$m['status'])?></option><?php endforeach;?></select></label>
<h3>Componentes</h3>
<?php foreach($items as $item):?>
<div class="card" style="padding:10px">
<label><input type="checkbox" name="items[<?=$item['id']?>][enabled]" checked> <?=h($item['name'])?></label>
<div class="inline"><label>Obrigatório <input type="checkbox" name="items[<?=$item['id']?>][required]"></label>
<label>Consolidar <input type="checkbox" name="items[<?=$item['id']?>][summary]" <?=$item['summary_enabled']?'checked':''?>></label>
<label>Limiar<input type="number" min="0" max="1" step="0.01" name="items[<?=$item['id']?>][threshold]" value="<?=h((string)$item['confidence_threshold'])?>"></label>
<input type="hidden" name="items[<?=$item['id']?>][sort_order]" value="<?=$item['sort_order']?>">
</div></div><?php endforeach;?>
<label>Observações<textarea name="notes"></textarea></label><button>Adicionar protocolo</button></form>
</section></div>

<h2>Componentes cadastrados</h2>
<table><tr><th>Cor</th><th>Código</th><th>Nome</th><th>Categoria</th><th>Unidade</th><th>IA</th><th>Anotação</th><th>Consolida</th><th>Limiar</th><th>YOLO</th><th>Ativo</th><th></th></tr>
<?php foreach($items as $i):?><tr><td><span style="display:inline-block;width:18px;height:18px;background:<?=h($i['color_hex'])?>"></span></td><td><?=h($i['code'])?></td><td><?=h($i['name'])?></td><td><?=h($i['category'])?></td><td><?=h($i['default_unit'])?></td><td><?=$i['ai_enabled']?'Sim':'Não'?></td><td><?=$i['annotation_enabled']?'Sim':'Não'?></td><td><?=$i['summary_enabled']?'Sim':'Não'?></td><td><?=h((string)$i['confidence_threshold'])?></td><td><?=h((string)$i['yolo_class_id'])?></td><td><?=$i['active']?'Sim':'Não'?></td><td><button type="button" onclick="document.getElementById('item<?=$i['id']?>').showModal()">Editar</button></td></tr><?php endforeach;?></table>

<?php foreach($items as $i):?>
<dialog id="item<?=$i['id']?>"><form method="post" class="card" style="min-width:420px">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_item"><input type="hidden" name="id" value="<?=$i['id']?>">
<h3>Editar <?=h($i['name'])?></h3>
<label>Código<input name="code" value="<?=h($i['code'])?>" required></label>
<label>Nome<input name="name" value="<?=h($i['name'])?>" required></label>
<label>Categoria<input name="category" value="<?=h($i['category'])?>"></label>
<label>Cor<input type="color" name="color_hex" value="<?=h($i['color_hex'])?>"></label>
<label>Unidade<input name="default_unit" value="<?=h($i['default_unit'])?>"></label>
<label>Confiança mínima<input type="number" min="0" max="1" step="0.01" name="confidence_threshold" value="<?=h((string)$i['confidence_threshold'])?>"></label>
<label>ID da classe YOLO<input type="number" name="yolo_class_id" value="<?=h((string)$i['yolo_class_id'])?>"></label>
<label>Ordem<input type="number" name="sort_order" value="<?=$i['sort_order']?>"></label>
<label><input type="checkbox" name="active" <?=$i['active']?'checked':''?>> Ativo</label>
<label><input type="checkbox" name="ai_enabled" <?=$i['ai_enabled']?'checked':''?>> IA</label>
<label><input type="checkbox" name="annotation_enabled" <?=$i['annotation_enabled']?'checked':''?>> Anotação</label>
<label><input type="checkbox" name="summary_enabled" <?=$i['summary_enabled']?'checked':''?>> Consolidação</label>
<label>Observações<textarea name="notes"><?=h($i['notes'])?></textarea></label>
<button>Salvar</button> <button type="button" onclick="this.closest('dialog').close()">Cancelar</button>
</form></dialog>
<?php endforeach;?>

<h2>Protocolos cadastrados</h2>
<?php foreach($protocols as $p):
$selected=[];foreach($protocolItems[(int)$p['id']]??[] as $pi){$selected[(int)$pi['item_type_id']]=$pi;}
?><section class="card"><h3><?=h($p['name'])?> <small class="muted">(<?=h($p['code'])?>)</small></h3>
<p>Campos: mínimo <?=$p['min_fields']?> · válidos <?=$p['min_valid_fields']?> · escala <?=h($p['default_scale_label'])?> · qualidade <?=$p['require_quality']?'obrigatória':'opcional'?></p>
<p><?php foreach($protocolItems[(int)$p['id']]??[] as $pi):?><span class="button" style="margin:3px;background:#64748b"><?=h($pi['name'])?> · <?=h((string)$pi['confidence_threshold'])?></span><?php endforeach;?></p>
<button type="button" onclick="document.getElementById('protocol<?=$p['id']?>').showModal()">Editar protocolo</button>
</section>
<dialog id="protocol<?=$p['id']?>"><form method="post" class="card" style="min-width:520px">
<input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="save_protocol"><input type="hidden" name="id" value="<?=$p['id']?>">
<h3>Editar <?=h($p['name'])?></h3>
<label>Código<input name="code" value="<?=h($p['code'])?>" required></label><label>Nome<input name="name" value="<?=h($p['name'])?>" required></label>
<div class="inline"><label>Campos mínimos<input type="number" min="1" name="min_fields" value="<?=$p['min_fields']?>"></label><label>Campos válidos mínimos<input type="number" min="1" name="min_valid_fields" value="<?=$p['min_valid_fields']?>"></label></div>
<div class="inline"><label>Escala padrão<input name="default_scale_label" value="<?=h($p['default_scale_label'])?>"></label><label>Magnificação<input type="number" step="0.001" name="default_magnification" value="<?=h((string)$p['default_magnification'])?>"></label></div>
<label><input type="checkbox" name="active" <?=$p['active']?'checked':''?>> Ativo</label>
<label><input type="checkbox" name="require_quality" <?=$p['require_quality']?'checked':''?>> Exigir controle de qualidade</label>
<label>Modelo padrão<select name="default_model_id"><option value="0">Nenhum</option><?php foreach($models as $m):?><option value="<?=$m['id']?>" <?=((int)$p['default_model_id']===(int)$m['id'])?'selected':''?>><?=h($m['name'].' '.$m['version'].' · '.$m['status'])?></option><?php endforeach;?></select></label>
<h4>Componentes</h4>
<?php foreach($items as $item):$sel=$selected[(int)$item['id']]??null;?>
<div class="card" style="padding:10px">
<label><input type="checkbox" name="items[<?=$item['id']?>][enabled]" <?=$sel?'checked':''?>> <?=h($item['name'])?></label>
<div class="inline">
<label>Obrigatório <input type="checkbox" name="items[<?=$item['id']?>][required]" <?=($sel&&$sel['required_item'])?'checked':''?>></label>
<label>Consolidar <input type="checkbox" name="items[<?=$item['id']?>][summary]" <?=($sel&&$sel['summary_enabled'])?'checked':''?>></label>
<label>Limiar<input type="number" min="0" max="1" step="0.01" name="items[<?=$item['id']?>][threshold]" value="<?=h((string)($sel['confidence_threshold']??$item['confidence_threshold']))?>"></label>
<input type="hidden" name="items[<?=$item['id']?>][sort_order]" value="<?=h((string)($sel['sort_order']??$item['sort_order']))?>">
</div></div>
<?php endforeach;?>
<label>Observações<textarea name="notes"><?=h($p['notes'])?></textarea></label>
<button>Salvar protocolo</button> <button type="button" onclick="this.closest('dialog').close()">Cancelar</button>
</form></dialog>
<?php endforeach;?>
</main></body></html>