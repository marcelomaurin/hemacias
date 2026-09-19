<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

$page = (string)($_GET['page'] ?? 'dashboard');
$error = '';
$ok = '';

if ($page === 'logout') {
    session_destroy();
    header('Location: index.php?page=login');
    exit;
}

if ($page === 'login') {
    if (current_user()) {
        header('Location: index.php');
        exit;
    }
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        csrf_check();
        $st = db()->prepare('SELECT * FROM users WHERE email=? AND active=1');
        $st->execute([strtolower(trim((string)($_POST['email'] ?? '')))]);
        $user = $st->fetch();
        if ($user && password_verify((string)($_POST['password'] ?? ''), $user['password_hash'])) {
            session_regenerate_id(true);
            $_SESSION['user_id'] = (int)$user['id'];
            audit('LOGIN','user',(int)$user['id']);
            header('Location: index.php');
            exit;
        }
        $error = 'Usuário ou senha inválidos.';
    }
    ?><!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Hemácias</title>
    <link rel="stylesheet" href="assets/style.css"></head><body><main class="narrow">
    <h1>Hemácias</h1><p>Gestão de pacientes, amostras e contagens.</p>
    <?php if ($error): ?><div class="error"><?=h($error)?></div><?php endif; ?>
    <form method="post" class="card">
    <input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
    <label>E-mail<input type="email" name="email" required></label>
    <label>Senha<input type="password" name="password" required></label>
    <button>Entrar</button></form></main></body></html><?php
    exit;
}

$user = require_login();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string)($_POST['action'] ?? '');

    try {
        if (($user['role'] ?? '') === 'LEITURA') {
            throw new RuntimeException('Este perfil possui somente permissão de leitura.');
        }
        if ($action === 'patient_create') {
            $name = trim((string)$_POST['name']);
            if ($name === '') throw new RuntimeException('Nome obrigatório.');
            $st = db()->prepare('INSERT INTO patients(external_id,name,birth_date,sex,document,notes) VALUES(?,?,?,?,?,?)');
            $st->execute([
                trim((string)$_POST['external_id']) ?: null, $name,
                $_POST['birth_date'] ?: null, $_POST['sex'] ?: null,
                trim((string)$_POST['document']) ?: null, trim((string)$_POST['notes']) ?: null
            ]);
            $id=(int)db()->lastInsertId(); audit('CREATE','patient',$id);
            header('Location: index.php?page=patient&id='.$id); exit;
        }

        if ($action === 'sample_create') {
            $patientId=(int)$_POST['patient_id'];
            $code=trim((string)$_POST['sample_code']);
            if ($patientId<1 || $code==='') throw new RuntimeException('Paciente e código da amostra são obrigatórios.');
            $st=db()->prepare('INSERT INTO samples(patient_id,sample_code,collected_at,sample_type,notes,created_by) VALUES(?,?,?,?,?,?)');
            $st->execute([$patientId,$code,$_POST['collected_at']?:null,$_POST['sample_type']?:'sangue',$_POST['notes']?:null,(int)$user['id']]);
            $id=(int)db()->lastInsertId(); audit('CREATE','sample',$id);
            header('Location: index.php?page=sample&id='.$id); exit;
        }

        if ($action === 'manual_count') {
            $sampleId=(int)$_POST['sample_id'];
            $qty=max(0,(int)$_POST['quantity']);
            $pdo=db(); $pdo->beginTransaction();
            $st=$pdo->prepare('INSERT INTO counts(sample_id,method,scale_label,magnification,total_cells,notes,source,created_by) VALUES(?,?,?,?,?,?,\'WEB\',?)');
            $st->execute([$sampleId,'manual',$_POST['scale_label']?:null,$_POST['magnification']?:null,$qty,$_POST['notes']?:null,(int)$user['id']]);
            $countId=(int)$pdo->lastInsertId();
            $st=$pdo->prepare('INSERT INTO count_components(count_id,component_code,component_name,quantity,unit) VALUES(?,?,?,?,?)');
            $st->execute([$countId,$_POST['component_code']?:'hemacia',$_POST['component_name']?:'Hemácia',$qty,$_POST['unit']?:'células/campo']);
            $pdo->commit(); audit('CREATE','count',$countId);
            header('Location: index.php?page=sample&id='.$sampleId); exit;
        }

        if ($action === 'user_create') {
            require_admin($user);
            if (!filter_var($_POST['email'] ?? '', FILTER_VALIDATE_EMAIL)) throw new RuntimeException('E-mail inválido.');
            if (strlen((string)$_POST['password']) < 10) throw new RuntimeException('Senha deve ter ao menos 10 caracteres.');
            $st=db()->prepare('INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,?)');
            $st->execute([trim((string)$_POST['name']),strtolower(trim((string)$_POST['email'])),password_hash((string)$_POST['password'],PASSWORD_DEFAULT),$_POST['role']]);
            audit('CREATE','user',(int)db()->lastInsertId());
            header('Location: index.php?page=users'); exit;
        }
    } catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        $error=$e->getMessage();
    }
}

function layout_start(array $user, string $title): void { ?>
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title><?=h($title)?> - Hemácias</title><link rel="stylesheet" href="assets/style.css"></head><body>
<header><strong>Hemácias</strong><nav>
<a href="index.php">Dashboard</a><a href="index.php?page=patients">Pacientes</a><a href="dataset.php">Dataset</a>
<?php if ($user['role']==='ADMIN'): ?><a href="index.php?page=users">Gestão</a><?php endif; ?>
<a href="index.php?page=logout">Sair (<?=h($user['name'])?>)</a></nav></header><main class="container">
<?php }
function layout_end(): void { echo '</main></body></html>'; }

if ($page === 'patients') {
    $q=trim((string)($_GET['q']??''));
    $st=db()->prepare('SELECT * FROM patients WHERE name LIKE ? OR external_id LIKE ? ORDER BY created_at DESC LIMIT 100');
    $like='%'.$q.'%'; $st->execute([$like,$like]); $patients=$st->fetchAll();
    layout_start($user,'Pacientes'); ?>
    <h1>Pacientes</h1><?php if($error):?><div class="error"><?=h($error)?></div><?php endif;?>
    <div class="grid"><section class="card"><h2>Novo paciente</h2>
    <form method="post"><input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="patient_create">
    <label>Identificador externo<input name="external_id"></label><label>Nome<input name="name" required></label>
    <label>Nascimento<input type="date" name="birth_date"></label><label>Sexo/descrição<input name="sex"></label>
    <label>Documento/identificador<input name="document"></label><label>Observações<textarea name="notes"></textarea></label><button>Cadastrar</button></form></section>
    <section class="card"><h2>Pesquisa</h2><form method="get"><input type="hidden" name="page" value="patients"><label>Nome ou ID<input name="q" value="<?=h($q)?>"></label><button>Pesquisar</button></form></section></div>
    <table><tr><th>ID</th><th>Identificador</th><th>Nome</th><th>Nascimento</th></tr>
    <?php foreach($patients as $p):?><tr><td><?=$p['id']?></td><td><?=h($p['external_id'])?></td><td><a href="index.php?page=patient&id=<?=$p['id']?>"><?=h($p['name'])?></a></td><td><?=h($p['birth_date'])?></td></tr><?php endforeach;?></table>
    <?php layout_end(); exit;
}

if ($page === 'patient') {
    $id=(int)($_GET['id']??0); $st=db()->prepare('SELECT * FROM patients WHERE id=?');$st->execute([$id]);$patient=$st->fetch();
    if(!$patient){http_response_code(404);exit('Paciente não encontrado.');}
    $st=db()->prepare('SELECT * FROM samples WHERE patient_id=? ORDER BY created_at DESC');$st->execute([$id]);$samples=$st->fetchAll();
    layout_start($user,'Paciente'); ?>
    <h1><?=h($patient['name'])?></h1><div class="card"><b>ID externo:</b> <?=h($patient['external_id'])?> &nbsp; <b>Nascimento:</b> <?=h($patient['birth_date'])?></div>
    <div class="grid"><section class="card"><h2>Nova amostra</h2><form method="post">
    <input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="sample_create"><input type="hidden" name="patient_id" value="<?=$id?>">
    <label>Código da amostra<input name="sample_code" required></label><label>Coleta<input type="datetime-local" name="collected_at"></label>
    <label>Tipo<input name="sample_type" value="sangue"></label><label>Observações<textarea name="notes"></textarea></label><button>Criar amostra</button></form></section></div>
    <h2>Amostras</h2><table><tr><th>Código</th><th>Data</th><th>Status</th></tr><?php foreach($samples as $s):?>
    <tr><td><a href="index.php?page=sample&id=<?=$s['id']?>"><?=h($s['sample_code'])?></a></td><td><?=h($s['created_at'])?></td><td><?=h($s['status'])?></td></tr><?php endforeach;?></table>
    <?php layout_end();exit;
}

if ($page === 'count') {
    $id=(int)($_GET['id']??0);
    $st=db()->prepare(
        'SELECT c.*,s.sample_code,s.id sample_id,p.name patient_name,p.id patient_id
         FROM counts c
         JOIN samples s ON s.id=c.sample_id
         JOIN patients p ON p.id=s.patient_id
         WHERE c.id=?'
    );
    $st->execute([$id]);
    $count=$st->fetch();
    if(!$count){http_response_code(404);exit('Contagem não encontrada.');}

    $st=db()->prepare('SELECT * FROM count_components WHERE count_id=? ORDER BY id');
    $st->execute([$id]);
    $components=$st->fetchAll();

    $st=db()->prepare('SELECT * FROM sample_images WHERE count_id=? ORDER BY created_at');
    $st->execute([$id]);
    $images=$st->fetchAll();

    layout_start($user,'Contagem'); ?>
    <h1>Contagem #<?=$count['id']?></h1>
    <div class="card">
      <b>Paciente:</b> <a href="index.php?page=patient&id=<?=$count['patient_id']?>"><?=h($count['patient_name'])?></a>
      &nbsp; <b>Amostra:</b> <a href="index.php?page=sample&id=<?=$count['sample_id']?>"><?=h($count['sample_code'])?></a><br>
      <b>Método:</b> <?=h($count['method'])?> &nbsp;
      <b>Versão:</b> <?=h($count['algorithm_version'])?> &nbsp;
      <b>Escala:</b> <?=h($count['scale_label'])?> &nbsp;
      <b>Magnificação:</b> <?=h((string)$count['magnification'])?> &nbsp;
      <b>Pixel:</b> <?=h((string)$count['pixel_size_um'])?> µm<br>
      <b>Foco:</b> <?=h((string)$count['focus_score'])?> &nbsp;
      <b>Qualidade:</b> <?=h($count['image_quality'])?> &nbsp;
      <b>Origem:</b> <?=h($count['source'])?> &nbsp;
      <b>Data:</b> <?=h($count['created_at'])?>
    </div>

    <h2>Componentes identificados</h2>
    <table><tr><th>Componente</th><th>Quantidade</th><th>Unidade</th><th>Confiança</th></tr>
    <?php foreach($components as $component):?>
      <tr><td><?=h($component['component_name'])?></td><td><?=$component['quantity']?></td><td><?=h($component['unit'])?></td><td><?=h((string)$component['confidence'])?></td></tr>
    <?php endforeach;?></table>

    <h2>Imagem e identificações</h2>
    <?php foreach($images as $img):
      $detections=[];
      foreach($components as $component){
          $meta=json_decode((string)($component['metadata_json']??''),true);
          if(is_array($meta) && is_array($meta['detections']??null)){
              $detections=array_merge($detections,$meta['detections']);
          }
      }
      $w=max(1,(int)($img['width_px']??1));
      $hgt=max(1,(int)($img['height_px']??1));
    ?>
    <div class="card">
      <div style="position:relative;display:inline-block;max-width:100%">
        <img src="image.php?id=<?=$img['id']?>" alt="Amostra" style="display:block;max-width:100%;height:auto">
        <svg viewBox="0 0 <?=$w?> <?=$hgt?>" preserveAspectRatio="xMidYMid meet"
             style="position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none">
          <?php foreach($detections as $det):
            $x=(float)($det['x']??0); $y=(float)($det['y']??0); $r=max(2.0,(float)($det['radius_px']??4));
            $polygon=is_array($det['polygon']??null)?$det['polygon']:[];
            $points=[];
            foreach($polygon as $point){
                if(is_array($point) && count($point)>=2){
                    $points[]=(float)$point[0].','.(float)$point[1];
                }
            }
          ?>
            <?php if(count($points)>=3):?>
              <polygon points="<?=h(implode(' ',$points))?>" fill="none" stroke="#00ff00" stroke-width="2"/>
            <?php else:?>
              <circle cx="<?=$x?>" cy="<?=$y?>" r="<?=$r?>" fill="none" stroke="#00ff00" stroke-width="2"/>
            <?php endif;?>
          <?php endforeach;?>
        </svg>
      </div>
      <p><small class="muted"><?=h($img['original_name'])?> · <?=h($img['scale_label'])?> · <?=count($detections)?> identificação(ões)</small></p>
      <p><a class="button" href="annotation.php?image_id=<?=$img['id']?>">Revisar / Anotar imagem</a></p>
    </div>
    <?php endforeach; ?>

    <?php layout_end();exit;
}

if ($page === 'sample') {
    $id=(int)($_GET['id']??0);
    $st=db()->prepare('SELECT s.*,p.name patient_name,p.id patient_id FROM samples s JOIN patients p ON p.id=s.patient_id WHERE s.id=?');$st->execute([$id]);$sample=$st->fetch();
    if(!$sample){http_response_code(404);exit('Amostra não encontrada.');}
    $st=db()->prepare('SELECT c.*,GROUP_CONCAT(CONCAT(cc.component_name,\': \',cc.quantity,\' \',cc.unit) SEPARATOR \' | \') components FROM counts c LEFT JOIN count_components cc ON cc.count_id=c.id WHERE c.sample_id=? GROUP BY c.id ORDER BY c.created_at DESC');$st->execute([$id]);$counts=$st->fetchAll();
    $st=db()->prepare('SELECT * FROM sample_images WHERE sample_id=? ORDER BY created_at DESC');$st->execute([$id]);$images=$st->fetchAll();
    layout_start($user,'Amostra'); ?>
    <h1>Amostra <?=h($sample['sample_code'])?></h1><p>Paciente: <a href="index.php?page=patient&id=<?=$sample['patient_id']?>"><?=h($sample['patient_name'])?></a></p>
    <div class="grid"><section class="card"><h2>Contagem manual</h2><form method="post">
    <input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="manual_count"><input type="hidden" name="sample_id" value="<?=$id?>">
    <label>Componente<select name="component_code"><option value="hemacia">Hemácia</option><option value="leucocito">Leucócito</option><option value="plaqueta">Plaqueta</option><option value="outro">Outro</option></select></label>
    <label>Nome do componente<input name="component_name" value="Hemácia"></label><label>Quantidade<input type="number" min="0" name="quantity" required></label>
    <label>Unidade<input name="unit" value="células/campo"></label><label>Escala<input name="scale_label" placeholder="Ex.: 40x"></label>
    <label>Magnificação<input type="number" step="0.001" name="magnification"></label><label>Observações<textarea name="notes"></textarea></label><button>Registrar contagem</button></form></section></div>
    <h2>Contagens</h2><table><tr><th>Data</th><th>Origem</th><th>Método</th><th>Escala</th><th>Componentes</th></tr>
    <?php foreach($counts as $c):?><tr><td><a href="index.php?page=count&id=<?=$c['id']?>"><?=h($c['created_at'])?></a></td><td><?=h($c['source'])?></td><td><?=h($c['method'])?></td><td><?=h($c['scale_label'])?></td><td><?=h($c['components'])?></td></tr><?php endforeach;?></table>
    <h2>Imagens</h2><div class="grid"><?php foreach($images as $img):?><div class="card"><a href="image.php?id=<?=$img['id']?>" target="_blank"><img src="image.php?id=<?=$img['id']?>" alt="" style="max-width:100%;max-height:260px"></a><br><small class="muted"><?=h($img['created_at'])?> · <?=h($img['scale_label'])?></small><p><a class="button" href="annotation.php?image_id=<?=$img['id']?>">Anotar / Revisar</a></p></div><?php endforeach;?></div>
    <?php layout_end();exit;
}

if ($page === 'users') {
    require_admin($user); $users=db()->query('SELECT id,name,email,role,active,created_at FROM users ORDER BY name')->fetchAll();
    layout_start($user,'Gestão'); ?>
    <h1>Gestão de usuários</h1><?php if($error):?><div class="error"><?=h($error)?></div><?php endif;?>
    <div class="grid"><section class="card"><h2>Novo usuário</h2><form method="post">
    <input type="hidden" name="csrf" value="<?=h(csrf_token())?>"><input type="hidden" name="action" value="user_create">
    <label>Nome<input name="name" required></label><label>E-mail<input type="email" name="email" required></label>
    <label>Senha<input type="password" name="password" minlength="10" required></label><label>Perfil<select name="role"><option>OPERADOR</option><option>LEITURA</option><option>ADMIN</option></select></label><button>Criar usuário</button></form></section></div>
    <table><tr><th>Nome</th><th>E-mail</th><th>Perfil</th><th>Ativo</th></tr><?php foreach($users as $u):?><tr><td><?=h($u['name'])?></td><td><?=h($u['email'])?></td><td><?=h($u['role'])?></td><td><?=$u['active']?'Sim':'Não'?></td></tr><?php endforeach;?></table>
    <?php layout_end();exit;
}

$metrics=[
    'patients'=>(int)db()->query('SELECT COUNT(*) FROM patients')->fetchColumn(),
    'samples'=>(int)db()->query('SELECT COUNT(*) FROM samples')->fetchColumn(),
    'counts'=>(int)db()->query('SELECT COUNT(*) FROM counts')->fetchColumn(),
    'images'=>(int)db()->query('SELECT COUNT(*) FROM sample_images')->fetchColumn(),
];
$recent=db()->query('SELECT c.id,c.created_at,c.source,s.sample_code,p.name patient_name FROM counts c JOIN samples s ON s.id=c.sample_id JOIN patients p ON p.id=s.patient_id ORDER BY c.created_at DESC LIMIT 10')->fetchAll();
layout_start($user,'Dashboard'); ?>
<h1>Dashboard</h1><div class="grid"><div class="card"><div class="metric"><?=$metrics['patients']?></div>Pacientes</div><div class="card"><div class="metric"><?=$metrics['samples']?></div>Amostras</div><div class="card"><div class="metric"><?=$metrics['counts']?></div>Contagens</div><div class="card"><div class="metric"><?=$metrics['images']?></div>Imagens</div></div>
<h2>Últimas contagens</h2><table><tr><th>Data</th><th>Paciente</th><th>Amostra</th><th>Origem</th></tr><?php foreach($recent as $r):?><tr><td><?=h($r['created_at'])?></td><td><?=h($r['patient_name'])?></td><td><?=h($r['sample_code'])?></td><td><?=h($r['source'])?></td></tr><?php endforeach;?></table>
<?php layout_end();
