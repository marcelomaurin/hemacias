<?php
declare(strict_types=1);

require __DIR__ . '/lib/bootstrap.php';

$page = (string)($_GET['page'] ?? 'dashboard');
$error = '';
$ok = '';

if ($page === 'logout') {
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'], $params['secure'], $params['httponly']);
    }
    session_destroy();
    header('Location: index.php?page=login');
    exit;
}

if ($page === 'login') {
    $currentUser = current_user();
    if ($currentUser) {
        header('Location: index.php');
        exit;
    }

    $dbInstalled = Database::tableExists('users');

    // Fallback de login tradicional via POST
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        csrf_check();
        $email = strtolower(trim((string)($_POST['email'] ?? '')));
        $password = (string)($_POST['password'] ?? '');
        try {
            $user = UserModel::authenticate($email, $password);
            if ($user) {
                session_regenerate_id(true);
                $_SESSION['user_id'] = (int)$user['id'];
                audit('LOGIN', 'user', (int)$user['id']);
                header('Location: index.php');
                exit;
            }
            $error = 'Usuário ou senha inválidos.';
        } catch (Throwable $e) {
            $error = 'Erro ao processar login: ' . $e->getMessage();
        }
    }
    ?><!doctype html>
    <html lang="pt-BR">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title><?=h(App::NAME)?> - Entrar</title>
        <link rel="stylesheet" href="assets/style.css">
    </head>
    <body>
    <main class="narrow">
        <h1><?=h(App::NAME)?></h1>
        <p>Gestão de pacientes, amostras e contagens celulares.</p>

        <?php if (!$dbInstalled): ?>
            <div style="background: rgba(234, 179, 8, 0.15); border: 1px solid #eab308; color: #fef08a; padding: 12px; border-radius: 6px; margin-bottom: 16px;">
                <strong>Aviso:</strong> O banco de dados ainda não foi inicializado.<br>
                <a href="install.php" style="color: #60a5fa; font-weight: bold; text-decoration: underline;">Clique aqui para abrir o Painel de Auto-Instalação &rarr;</a>
            </div>
        <?php endif; ?>

        <div id="loginFeedback">
            <?php if ($error): ?><div class="error"><?=h($error)?></div><?php endif; ?>
        </div>

        <form id="loginForm" method="post" class="card" onsubmit="handleAjaxLogin(event)">
            <input type="hidden" name="csrf" id="loginCsrf" value="<?=h(csrf_token())?>">
            <label>E-mail
                <input type="email" name="email" id="loginEmail" required autofocus>
            </label>
            <label>Senha
                <input type="password" name="password" id="loginPassword" required>
            </label>
            <button type="submit" id="btnLogin">Entrar</button>
        </form>

        <div style="margin-top: 15px; text-align: center; font-size: 12px; color: #888;">
            <?=h(App::NAME)?> v<?=h(App::getVersion())?> | <a href="install.php" style="color: #60a5fa;">Auto-Instalador & Versão</a>
        </div>
    </main>

    <script>
    async function handleAjaxLogin(e) {
        e.preventDefault();
        const btn = document.getElementById('btnLogin');
        const fb = document.getElementById('loginFeedback');
        const email = document.getElementById('loginEmail').value;
        const password = document.getElementById('loginPassword').value;
        const csrf = document.getElementById('loginCsrf').value;

        btn.disabled = true;
        btn.innerText = 'Autenticando...';
        fb.innerHTML = '';

        try {
            const res = await fetch('ws.php', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    action: 'auth_login',
                    email: email,
                    password: password,
                    csrf: csrf
                })
            });
            const json = await res.json();

            if (json.ok) {
                fb.innerHTML = '<div style="background:#14532d;color:#86efac;padding:10px;border-radius:6px;margin-bottom:10px;">Login realizado! Redirecionando...</div>';
                window.location.href = (json.data && json.data.redirect) ? json.data.redirect : 'index.php';
            } else {
                fb.innerHTML = '<div class="error">' + (json.error || 'Falha na autenticação.') + '</div>';
                btn.disabled = false;
                btn.innerText = 'Entrar';
            }
        } catch (err) {
            document.getElementById('loginForm').submit();
        }
    }
    </script>
    </body>
    </html><?php
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
            $id = PatientModel::create($_POST, (int)$user['id']);
            header('Location: index.php?page=patient&id=' . $id);
            exit;
        }

        if ($action === 'sample_create') {
            $id = SampleModel::create($_POST, (int)$user['id']);
            header('Location: index.php?page=sample&id=' . $id);
            exit;
        }

        if ($action === 'manual_count') {
            $sampleId = (int)$_POST['sample_id'];
            $itemTypeId = (int)($_POST['item_type_id'] ?? 0);
            $qty = max(0, (int)$_POST['quantity']);
            $st = db()->prepare('SELECT * FROM count_item_types WHERE id=? AND active=1');
            $st->execute([$itemTypeId]);
            $item = $st->fetch();
            if (!$item) throw new RuntimeException('Componente de contagem inválido.');

            $pdo = db();
            $pdo->beginTransaction();
            $st = $pdo->prepare('INSERT INTO counts(sample_id,method,scale_label,magnification,total_cells,notes,source,created_by) VALUES(?,?,?,?,?,?,'\'WEB\'',?)');
            $st->execute([$sampleId, 'manual', $_POST['scale_label'] ?: null, $_POST['magnification'] ?: null, $qty, $_POST['notes'] ?: null, (int)$user['id']]);
            $countId = (int)$pdo->lastInsertId();
            $st = $pdo->prepare('INSERT INTO count_components(count_id,item_type_id,component_code,component_name,quantity,unit) VALUES(?,?,?,?,?,?)');
            $st->execute([$countId, $itemTypeId, $item['code'], $item['name'], $qty, $item['default_unit']]);
            $pdo->commit();
            audit('CREATE', 'count', $countId);
            header('Location: index.php?page=sample&id=' . $sampleId);
            exit;
        }

        if ($action === 'user_create') {
            require_admin($user);
            if (!filter_var($_POST['email'] ?? '', FILTER_VALIDATE_EMAIL)) throw new RuntimeException('E-mail inválido.');
            if (strlen((string)$_POST['password']) < 10) throw new RuntimeException('Senha deve ter ao menos 10 caracteres.');
            UserModel::create($_POST, (int)$user['id']);
            header('Location: index.php?page=users');
            exit;
        }
    } catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        $error = $e->getMessage();
    }
}

function layout_start(array $user, string $title): void { ?>
<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title><?=h($title)?> - <?=h(App::NAME)?></title>
    <link rel="stylesheet" href="assets/style.css">
</head>
<body>
<header>
    <strong><?=h(App::NAME)?></strong>
    <nav>
        <a href="index.php">Dashboard</a>
        <a href="index.php?page=patients">Pacientes</a>
        <a href="dataset.php">Dataset</a>
        <?php if ($user['role'] === 'ADMIN'): ?>
            <a href="resources.php">Recursos</a>
            <a href="models.php">Modelos IA</a>
            <a href="index.php?page=users">Usuários</a>
            <a href="install.php">Sistema</a>
        <?php endif; ?>
        <a href="index.php?page=logout">Sair (<?=h($user['name'])?>)</a>
    </nav>
</header>
<main class="container">
<?php }

function layout_end(): void {
    $versionRow = VersionModel::getLatest();
    $schemaVer = $versionRow ? (int)$versionRow['schema_version'] : 0;
    ?>
</main>
<footer style="margin-top: 40px; padding: 20px; text-align: center; font-size: 12px; color: #888; border-top: 1px solid rgba(255,255,255,0.08);">
    <strong><?=h(App::NAME)?></strong> v<?=h(App::getVersion())?> |
    Banco de Dados: Schema v<?=h((string)$schemaVer)?>
    <?php if ($schemaVer >= App::SCHEMA_TARGET_VERSION): ?>
        <span style="color: #4ade80;">● Atualizado</span>
    <?php else: ?>
        <a href="install.php" style="color: #facc15;">▲ Atualização Pendente</a>
    <?php endif; ?>
    | <?=date('Y')?> Maurinsoft
</footer>
</body>
</html>
<?php }

if ($page === 'patients') {
    $q = trim((string)($_GET['q'] ?? ''));
    $patients = PatientModel::listAll($q);
    layout_start($user, 'Pacientes'); ?>
    <h1>Pacientes</h1><?php if ($error): ?><div class="error"><?=h($error)?></div><?php endif; ?>
    <div class="grid">
        <section class="card">
            <h2>Novo paciente</h2>
            <form method="post">
                <input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
                <input type="hidden" name="action" value="patient_create">
                <label>Identificador externo<input name="external_id"></label>
                <label>Nome<input name="name" required></label>
                <label>Nascimento<input type="date" name="birth_date"></label>
                <label>Sexo/descrição<input name="sex"></label>
                <label>Documento/identificador<input name="document"></label>
                <label>Observações<textarea name="notes"></textarea></label>
                <button>Cadastrar</button>
            </form>
        </section>
        <section class="card">
            <h2>Pesquisa</h2>
            <form method="get">
                <input type="hidden" name="page" value="patients">
                <label>Nome ou ID<input name="q" value="<?=h($q)?>"></label>
                <button>Pesquisar</button>
            </form>
        </section>
    </div>
    <table>
        <tr><th>ID</th><th>Identificador</th><th>Nome</th><th>Nascimento</th></tr>
        <?php foreach ($patients as $p): ?>
            <tr>
                <td><?=$p['id']?></td>
                <td><?=h($p['external_id'])?></td>
                <td><a href="index.php?page=patient&id=<?=$p['id']?>"><?=h($p['name'])?></a></td>
                <td><?=h($p['birth_date'])?></td>
            </tr>
        <?php endforeach; ?>
    </table>
    <?php layout_end(); exit;
}

if ($page === 'patient') {
    $id = (int)($_GET['id'] ?? 0);
    $patient = PatientModel::findById($id);
    if (!$patient) {
        http_response_code(404);
        exit('Paciente não encontrado.');
    }
    $samples = SampleModel::listByPatient($id);
    $protocols = db()->query('SELECT id,name FROM count_protocols WHERE active=1 ORDER BY name')->fetchAll();
    layout_start($user, 'Paciente'); ?>
    <h1><?=h($patient['name'])?></h1>
    <div class="card">
        <b>ID externo:</b> <?=h($patient['external_id'])?> &nbsp; <b>Nascimento:</b> <?=h($patient['birth_date'])?>
    </div>
    <div class="grid">
        <section class="card">
            <h2>Nova amostra</h2>
            <form method="post">
                <input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
                <input type="hidden" name="action" value="sample_create">
                <input type="hidden" name="patient_id" value="<?=$id?>">
                <label>Código da amostra<input name="sample_code" required></label>
                <label>Coleta<input type="datetime-local" name="collected_at"></label>
                <label>Tipo<input name="sample_type" value="sangue"></label>
                <label>Protocolo
                    <select name="protocol_id">
                        <?php foreach ($protocols as $p): ?>
                            <option value="<?=$p['id']?>"><?=h($p['name'])?></option>
                        <?php endforeach; ?>
                    </select>
                </label>
                <label>Observações<textarea name="notes"></textarea></label>
                <button>Criar amostra</button>
            </form>
        </section>
    </div>
    <h2>Amostras</h2>
    <table>
        <tr><th>Código</th><th>Protocolo</th><th>Data</th><th>Status</th></tr>
        <?php foreach ($samples as $s): ?>
            <tr>
                <td><a href="index.php?page=sample&id=<?=$s['id']?>"><?=h($s['sample_code'])?></a></td>
                <td><?=h($s['protocol_name'])?></td>
                <td><?=h($s['created_at'])?></td>
                <td><?=h($s['status'])?></td>
            </tr>
        <?php endforeach; ?>
    </table>
    <?php layout_end(); exit;
}

if ($page === 'sample') {
    $id = (int)($_GET['id'] ?? 0);
    $sample = SampleModel::findById($id);
    if (!$sample) {
        http_response_code(404);
        exit('Amostra não encontrada.');
    }
    $images = db()->prepare('SELECT * FROM sample_images WHERE sample_id=? ORDER BY created_at DESC');
    $images->execute([$id]);
    $images = $images->fetchAll();

    $counts = db()->prepare('SELECT * FROM counts WHERE sample_id=? ORDER BY created_at DESC');
    $counts->execute([$id]);
    $counts = $counts->fetchAll();

    $itemTypes = db()->query('SELECT * FROM count_item_types WHERE active=1 ORDER BY sort_order ASC, name ASC')->fetchAll();

    layout_start($user, 'Amostra ' . $sample['sample_code']); ?>
    <h1>Amostra: <?=h($sample['sample_code'])?></h1>
    <div class="card">
        <b>Paciente:</b> <a href="index.php?page=patient&id=<?=$sample['patient_id']?>"><?=h($sample['patient_name'])?></a> &nbsp;
        <b>Status:</b> <?=h($sample['status'])?> &nbsp;
        <b>Protocolo:</b> <?=h($sample['protocol_name'] ?? 'Nenhum')?>
    </div>

    <div class="grid">
        <section class="card">
            <h2>Contagem Manual</h2>
            <form method="post">
                <input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
                <input type="hidden" name="action" value="manual_count">
                <input type="hidden" name="sample_id" value="<?=$id?>">
                <label>Componente
                    <select name="item_type_id" required>
                        <?php foreach ($itemTypes as $it): ?>
                            <option value="<?=$it['id']?>"><?=h($it['name'])?> (<?=h($it['code'])?>)</option>
                        <?php endforeach; ?>
                    </select>
                </label>
                <label>Quantidade<input type="number" name="quantity" min="0" value="1" required></label>
                <label>Escala<input name="scale_label" placeholder="ex.: 100x"></label>
                <label>Magnificação<input type="number" step="0.01" name="magnification" placeholder="ex.: 100"></label>
                <label>Observações<textarea name="notes"></textarea></label>
                <button>Gravar Contagem</button>
            </form>
        </section>
    </div>

    <h2>Contagens Realizadas</h2>
    <table>
        <tr><th>ID</th><th>Método</th><th>Células</th><th>Data</th><th>Origem</th></tr>
        <?php foreach ($counts as $c): ?>
            <tr>
                <td><?=$c['id']?></td>
                <td><?=h($c['method'])?></td>
                <td><?=$c['total_cells']?></td>
                <td><?=h($c['created_at'])?></td>
                <td><?=h($c['source'])?></td>
            </tr>
        <?php endforeach; ?>
    </table>

    <h2>Imagens da Amostra</h2>
    <table>
        <tr><th>ID</th><th>Nome</th><th>Tamanho</th><th>Data</th></tr>
        <?php foreach ($images as $im): ?>
            <tr>
                <td><?=$im['id']?></td>
                <td><a href="image.php?id=<?=$im['id']?>" target="_blank"><?=h($im['original_name'])?></a></td>
                <td><?=number_format($im['file_size'] / 1024, 1)?> KB</td>
                <td><?=h($im['created_at'])?></td>
            </tr>
        <?php endforeach; ?>
    </table>
    <?php layout_end(); exit;
}

if ($page === 'users') {
    require_admin($user);
    $usersList = UserModel::listAll();
    layout_start($user, 'Usuários'); ?>
    <h1>Gestão de Usuários</h1>
    <?php if ($error): ?><div class="error"><?=h($error)?></div><?php endif; ?>
    <div class="grid">
        <section class="card">
            <h2>Novo Usuário</h2>
            <form method="post">
                <input type="hidden" name="csrf" value="<?=h(csrf_token())?>">
                <input type="hidden" name="action" value="user_create">
                <label>Nome<input name="name" required></label>
                <label>E-mail<input type="email" name="email" required></label>
                <label>Senha (mínimo 10 caracteres)<input type="password" name="password" minlength="10" required></label>
                <label>Perfil
                    <select name="role">
                        <option value="OPERADOR">OPERADOR</option>
                        <option value="ADMIN">ADMIN</option>
                        <option value="LEITURA">LEITURA</option>
                    </select>
                </label>
                <button>Cadastrar Usuário</button>
            </form>
        </section>
    </div>
    <table>
        <tr><th>ID</th><th>Nome</th><th>E-mail</th><th>Perfil</th><th>Ativo</th></tr>
        <?php foreach ($usersList as $u): ?>
            <tr>
                <td><?=$u['id']?></td>
                <td><?=h($u['name'])?></td>
                <td><?=h($u['email'])?></td>
                <td><?=h($u['role'])?></td>
                <td><?=$u['active'] ? 'Sim' : 'Não'?></td>
            </tr>
        <?php endforeach; ?>
    </table>
    <?php layout_end(); exit;
}

// Dashboard padrão
try {
    $patientCount = (int)db()->query('SELECT COUNT(*) FROM patients')->fetchColumn();
    $sampleCount = (int)db()->query('SELECT COUNT(*) FROM samples')->fetchColumn();
    $countTotal = (int)db()->query('SELECT COUNT(*) FROM counts')->fetchColumn();
    $imageCount = (int)db()->query('SELECT COUNT(*) FROM sample_images')->fetchColumn();
} catch (Throwable) {
    $patientCount = 0;
    $sampleCount = 0;
    $countTotal = 0;
    $imageCount = 0;
}

layout_start($user, 'Dashboard'); ?>
<h1>Dashboard</h1>
<div class="grid">
    <div class="card">
        <h3>Pacientes</h3>
        <p style="font-size: 32px; font-weight: bold; margin: 10px 0;"><?=number_format($patientCount)?></p>
        <a href="index.php?page=patients">Ver pacientes &rarr;</a>
    </div>
    <div class="card">
        <h3>Amostras</h3>
        <p style="font-size: 32px; font-weight: bold; margin: 10px 0;"><?=number_format($sampleCount)?></p>
        <p>Cadastradas no sistema</p>
    </div>
    <div class="card">
        <h3>Contagens</h3>
        <p style="font-size: 32px; font-weight: bold; margin: 10px 0;"><?=number_format($countTotal)?></p>
        <p>Manuais e por IA</p>
    </div>
    <div class="card">
        <h3>Imagens</h3>
        <p style="font-size: 32px; font-weight: bold; margin: 10px 0;"><?=number_format($imageCount)?></p>
        <a href="dataset.php">Gerenciador de Dataset &rarr;</a>
    </div>
</div>
<?php layout_end();
