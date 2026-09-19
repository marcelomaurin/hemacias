<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
$user=require_login();

$imageId=(int)($_GET['image_id']??0);
$st=db()->prepare(
    'SELECT i.*,s.sample_code,s.id sample_id,p.name patient_name,p.id patient_id
     FROM sample_images i
     JOIN samples s ON s.id=i.sample_id
     JOIN patients p ON p.id=s.patient_id
     WHERE i.id=?'
);
$st->execute([$imageId]);
$image=$st->fetch();
if(!$image){http_response_code(404);exit('Imagem não encontrada.');}

$annotationItems=db()->query(
    "SELECT id,code,name,color_hex
     FROM count_item_types
     WHERE active=1 AND annotation_enabled=1
     ORDER BY sort_order,name"
)->fetchAll();
$itemColors=[];
foreach($annotationItems as $item){$itemColors[$item['code']]=$item['color_hex'];}
?><!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Anotação - Hemácias</title>
<link rel="stylesheet" href="assets/style.css">
<link rel="stylesheet" href="assets/annotation.css">
</head>
<body>
<header><strong>Hemácias · Anotação</strong><nav>
<a href="index.php?page=sample&id=<?=$image['sample_id']?>">Voltar à amostra</a>
<a href="index.php?page=logout">Sair</a>
</nav></header>
<main class="container">
<h1>Anotar imagem</h1>
<div class="card">
<b>Paciente:</b> <?=h($image['patient_name'])?> ·
<b>Amostra:</b> <?=h($image['sample_code'])?> ·
<b>Imagem:</b> <?=h($image['original_name'])?> ·
<b>Escala:</b> <?=h($image['scale_label'])?>
</div>

<div class="annotation-toolbar card">
<label>Classe
<select id="classSelect">
<?php foreach($annotationItems as $item):?>
<option value="<?=h($item['code'].'|'.$item['name'])?>"><?=h($item['name'])?></option>
<?php endforeach;?></select></label>
<button type="button" id="finishPolygon">Finalizar polígono</button>
<button type="button" id="undoPoint">Desfazer ponto</button>
<button type="button" id="deleteSelected">Excluir selecionada</button>
<button type="button" id="importAuto">Importar detecção automática</button>
<button type="button" id="saveAnnotations">Salvar revisão</button>
<a class="button secondary" href="export_annotation.php?image_id=<?=$imageId?>&format=labelme">Exportar LabelMe</a>
<a class="button secondary" href="export_annotation.php?image_id=<?=$imageId?>&format=yolo">Exportar YOLO</a>
</div>

<div id="annotationStatus" class="card">Clique na imagem para adicionar pontos. Use no mínimo 3 pontos e finalize o polígono.</div>

<div class="annotation-layout">
<div class="annotation-stage" id="stage">
<img id="sampleImage" src="image.php?id=<?=$imageId?>" alt="Amostra">
<svg id="annotationSvg" viewBox="0 0 <?=max(1,(int)$image['width_px'])?> <?=max(1,(int)$image['height_px'])?>" preserveAspectRatio="xMidYMid meet"></svg>
</div>
<aside class="card annotation-list">
<h2>Anotações</h2>
<div id="annotationList"></div>
</aside>
</div>
</main>

<script>
const IMAGE_ID=<?=$imageId?>;
const IMAGE_W=<?=max(1,(int)$image['width_px'])?>;
const IMAGE_H=<?=max(1,(int)$image['height_px'])?>;
const CSRF=<?=json_encode(csrf_token())?>;
const READ_ONLY=<?=json_encode(($user['role']??'')==='LEITURA')?>;
const ITEM_COLORS=<?=json_encode($itemColors,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)?>;

const svg=document.getElementById('annotationSvg');
const statusBox=document.getElementById('annotationStatus');
const listBox=document.getElementById('annotationList');
let annotations=[];
let currentPoints=[];
let selectedIndex=-1;

function svgPoint(evt){
  const pt=svg.createSVGPoint(); pt.x=evt.clientX; pt.y=evt.clientY;
  const matrix=svg.getScreenCTM();
  const p=pt.matrixTransform(matrix.inverse());
  return [Math.max(0,Math.min(IMAGE_W,p.x)),Math.max(0,Math.min(IMAGE_H,p.y))];
}
function classInfo(){
  const [class_code,class_name]=document.getElementById('classSelect').value.split('|');
  return {class_code,class_name};
}
function colorFor(code){
  return ITEM_COLORS[code]||'#ffffff';
}
function redraw(){
  svg.innerHTML='';
  annotations.forEach((ann,idx)=>{
    const poly=document.createElementNS('http://www.w3.org/2000/svg','polygon');
    poly.setAttribute('points',ann.polygon.map(p=>p.join(',')).join(' '));
    poly.setAttribute('fill',idx===selectedIndex?'rgba(255,255,0,.15)':'rgba(0,0,0,0)');
    poly.setAttribute('stroke',colorFor(ann.class_code));
    poly.setAttribute('stroke-width',idx===selectedIndex?'3':'2');
    poly.dataset.index=idx;
    poly.addEventListener('click',e=>{e.stopPropagation();selectedIndex=idx;redraw();});
    svg.appendChild(poly);
  });
  if(currentPoints.length){
    const line=document.createElementNS('http://www.w3.org/2000/svg','polyline');
    line.setAttribute('points',currentPoints.map(p=>p.join(',')).join(' '));
    line.setAttribute('fill','none'); line.setAttribute('stroke','#ff00ff'); line.setAttribute('stroke-width','2');
    svg.appendChild(line);
    currentPoints.forEach(p=>{
      const c=document.createElementNS('http://www.w3.org/2000/svg','circle');
      c.setAttribute('cx',p[0]);c.setAttribute('cy',p[1]);c.setAttribute('r','3');c.setAttribute('fill','#ff00ff');svg.appendChild(c);
    });
  }
  listBox.innerHTML=annotations.map((a,i)=>
    '<button type="button" class="annotation-item '+(i===selectedIndex?'selected':'')+'" data-i="'+i+'">'+
    (i+1)+'. '+escapeHtml(a.class_name)+' ('+a.polygon.length+' pts)</button>'
  ).join('');
  listBox.querySelectorAll('.annotation-item').forEach(btn=>btn.onclick=()=>{selectedIndex=Number(btn.dataset.i);redraw();});
}
function escapeHtml(s){return String(s).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
svg.addEventListener('click',evt=>{
  if(READ_ONLY)return;
  currentPoints.push(svgPoint(evt)); selectedIndex=-1; redraw();
});
document.getElementById('finishPolygon').onclick=()=>{
  if(READ_ONLY)return;
  if(currentPoints.length<3){statusBox.textContent='O polígono precisa de pelo menos 3 pontos.';return;}
  annotations.push({...classInfo(),polygon:currentPoints,review_status:'APROVADA',notes:''});
  currentPoints=[];selectedIndex=annotations.length-1;redraw();
  statusBox.textContent='Polígono adicionado. Salve a revisão quando terminar.';
};
document.getElementById('undoPoint').onclick=()=>{if(!READ_ONLY){currentPoints.pop();redraw();}};
document.getElementById('deleteSelected').onclick=()=>{
  if(READ_ONLY)return;
  if(selectedIndex>=0){annotations.splice(selectedIndex,1);selectedIndex=-1;redraw();}
};
document.getElementById('importAuto').onclick=async()=>{
  if(READ_ONLY){statusBox.textContent='Perfil somente leitura.';return;}

  async function doImport(force=false){
    const body=new URLSearchParams({
      csrf:CSRF,action:'import_auto',image_id:String(IMAGE_ID),force:force?'1':'0'
    });
    statusBox.textContent='Importando detecções automáticas...';
    const response=await fetch('annotation_api.php',{
      method:'POST',
      headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body
    });
    const data=await response.json();

    if(!data.ok && data.requires_force){
      const confirmed=confirm(
        'Esta imagem já possui revisão humana. Reiniciar pelas detecções automáticas substituirá a revisão atual. Continuar?'
      );
      if(confirmed) return doImport(true);
      statusBox.textContent='Importação cancelada; a revisão humana foi preservada.';
      return;
    }
    if(!data.ok){statusBox.textContent='Erro: '+data.error;return;}

    statusBox.textContent='Importadas '+data.imported+' detecção(ões). Revise e salve antes de aprovar a imagem.';
    await loadAnnotations();
  }

  await doImport(false);
};

document.getElementById('saveAnnotations').onclick=async()=>{
  if(READ_ONLY){statusBox.textContent='Perfil somente leitura.';return;}
  if(currentPoints.length){statusBox.textContent='Finalize ou desfaça o polígono em edição antes de salvar.';return;}
  const body=new URLSearchParams({
    csrf:CSRF,action:'save_all',image_id:String(IMAGE_ID),annotations:JSON.stringify(annotations)
  });
  statusBox.textContent='Salvando...';
  const response=await fetch('annotation_api.php',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
  const data=await response.json();
  statusBox.textContent=data.ok?'Revisão salva: '+data.saved+' anotação(ões).':'Erro: '+data.error;
};
async function loadAnnotations(){
  const response=await fetch('annotation_api.php?image_id='+IMAGE_ID);
  const data=await response.json();
  if(data.ok){
    annotations=data.annotations.map(a=>({
      class_code:a.class_code,class_name:a.class_name,polygon:a.polygon,
      review_status:a.review_status,notes:a.notes||''
    }));
    redraw();
  }else statusBox.textContent='Erro ao carregar: '+data.error;
}
loadAnnotations();
</script>
</body></html>
