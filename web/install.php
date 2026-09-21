<?php
declare(strict_types=1);

require __DIR__ . '/lib/bootstrap.php';

$diag = Installer::getStatus();
$versionInfo = App::getInfo();
?>
<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Instalação & Atualização - <?=h(App::NAME)?></title>
    <link rel="stylesheet" href="assets/style.css">
    <style>
        .badge-ok { background: #166534; color: #bbf7d0; padding: 3px 8px; border-radius: 4px; font-weight: bold; font-size: 12px; }
        .badge-warn { background: #854d0e; color: #fef08a; padding: 3px 8px; border-radius: 4px; font-weight: bold; font-size: 12px; }
        .badge-err { background: #991b1b; color: #fecaca; padding: 3px 8px; border-radius: 4px; font-weight: bold; font-size: 12px; }
        .log-box { background: #0f172a; color: #38bdf8; padding: 12px; border-radius: 6px; font-family: monospace; font-size: 13px; max-height: 220px; overflow-y: auto; margin-top: 10px; display: none; white-space: pre-wrap; }
        .status-table td { padding: 6px 10px; border-bottom: 1px solid rgba(255,255,255,0.08); }
        .status-table tr:last-child td { border-bottom: none; }
        .step-card { margin-bottom: 20px; }
    </style>
</head>
<body>
<main class="narrow">
    <h1><?=h(App::NAME)?></h1>
    <p>Painel de Auto-Instalação & Controle de Versão</p>

    <!-- Diagnóstico de Conexão -->
    <div class="card step-card">
        <h2>Diagnóstico do Ambiente</h2>
        <table class="status-table" style="width: 100%;">
            <tr>
                <td><strong>Versão do Site:</strong></td>
                <td><?=h(App::VERSION)?> (Schema alvo: v<?=App::SCHEMA_TARGET_VERSION?>)</td>
            </tr>
            <tr>
                <td><strong>Versão PHP:</strong></td>
                <td><?=h(PHP_VERSION)?></td>
            </tr>
            <tr>
                <td><strong>Conexão MySQL:</strong></td>
                <td>
                    <?php if ($diag['connected']): ?>
                        <span class="badge-ok">Conectado (MySQL <?=h($diag['mysql_version'])?>)</span>
                    <?php else: ?>
                        <span class="badge-err">Erro de Conexão</span>
                    <?php endif; ?>
                </td>
            </tr>
            <tr>
                <td><strong>Tabelas do Banco:</strong></td>
                <td>
                    <?php if ($diag['installed']): ?>
                        <span class="badge-ok">Instaladas</span>
                    <?php else: ?>
                        <span class="badge-warn">Pendentes de Instalação</span>
                    <?php endif; ?>
                </td>
            </tr>
            <tr>
                <td><strong>Administrador:</strong></td>
                <td>
                    <?php if ($diag['has_admin']): ?>
                        <span class="badge-ok">Cadastrado</span>
                    <?php else: ?>
                        <span class="badge-warn">Não encontrado</span>
                    <?php endif; ?>
                </td>
            </tr>
        </table>

        <?php if (!$diag['connected']): ?>
            <div class="error" style="margin-top: 15px;">
                <strong>Atenção:</strong> <?=h($diag['error'])?><br>
                <small>Verifique as credenciais no arquivo <code>web/config.php</code> (host, usuário, senha e dbname com prefixo da hospedagem).</small>
            </div>
        <?php endif; ?>
    </div>

    <!-- Etapa 1: Instalação / Atualização do Banco -->
    <?php if ($diag['connected']): ?>
        <div class="card step-card">
            <h2>1. Banco de Dados & Migrações</h2>
            <?php if ($diag['installed'] && empty($diag['version_status']['pending_migrations'])): ?>
                <p>O banco de dados está atualizado na versão <strong>Schema v<?=h((string)($diag['version_status']['current_schema'] ?? 0))?></strong>.</p>
                <button type="button" id="btnReinstall" class="btn-secondary" onclick="runAutoInstall()">Verificar / Reaplicar Migrações</button>
            <?php else: ?>
                <p>O banco de dados precisa ser instalado ou atualizado com as novas tabelas e migrações.</p>
                <button type="button" id="btnInstall" onclick="runAutoInstall()">Instalar Banco Automaticamente</button>
            <?php endif; ?>
            <div id="installLog" class="log-box"></div>
        </div>

        <!-- Etapa 2: Criação do Administrador -->
        <div class="card step-card" id="adminSection" style="<?= $diag['has_admin'] ? 'display:none;' : '' ?>">
            <h2>2. Criar Primeiro Administrador</h2>
            <div id="adminMsg"></div>
            <form id="formAdmin" onsubmit="createAdmin(event)">
                <label>Chave de Instalação (config.php)
                    <input type="password" id="adminKey" required placeholder="install_key do config.php">
                </label>
                <label>Nome Completo
                    <input type="text" id="adminName" required placeholder="Ex.: Marcelo Maurin">
                </label>
                <label>E-mail
                    <input type="email" id="adminEmail" required placeholder="admin@seudominio.com.br">
                </label>
                <label>Senha de Acesso (mínimo 10 caracteres)
                    <input type="password" id="adminPassword" minlength="10" required placeholder="Senha forte">
                </label>
                <button type="submit" id="btnAdmin">Criar Administrador</button>
            </form>
        </div>

        <!-- Mensagem de Conclusão -->
        <div class="card step-card" id="readySection" style="<?= ($diag['installed'] && $diag['has_admin']) ? '' : 'display:none;' ?>">
            <h2>Sistema Pronto!</h2>
            <p>A auto-instalação e as migrações foram verificadas e já existe um administrador configurado.</p>
            <a href="index.php?page=login" style="display:inline-block; padding: 10px 20px; background: #2563eb; color: #fff; text-decoration: none; border-radius: 6px; font-weight: bold;">Ir para a Tela de Login</a>
        </div>
    <?php endif; ?>
</main>

<script>
async function runAutoInstall() {
    const btn = document.getElementById('btnInstall') || document.getElementById('btnReinstall');
    const logBox = document.getElementById('installLog');
    btn.disabled = true;
    btn.innerText = 'Instalando tabelas e migrações...';
    logBox.style.display = 'block';
    logBox.innerText = 'Disparando WebService de auto-instalação...\n';

    try {
        const res = await fetch('ws.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'auto_install' })
        });
        const json = await res.json();

        if (json.ok) {
            logBox.innerText += 'SUCESSO: ' + json.message + '\n';
            if (json.data && json.data.log) {
                json.data.log.forEach(msg => { logBox.innerText += ' - ' + msg + '\n'; });
            }
            btn.innerText = 'Instalação Concluída!';
            btn.style.background = '#166534';
            
            // Exibe formulário do admin caso não exista
            if (!json.data.has_admin) {
                document.getElementById('adminSection').style.display = 'block';
            } else {
                document.getElementById('readySection').style.display = 'block';
            }
        } else {
            logBox.innerText += 'ERRO: ' + (json.error || 'Falha desconhecida.') + '\n';
            btn.disabled = false;
            btn.innerText = 'Tentar Novamente';
        }
    } catch (err) {
        logBox.innerText += 'ERRO DE REQUISIÇÃO: ' + err.message + '\n';
        btn.disabled = false;
        btn.innerText = 'Tentar Novamente';
    }
}

async function createAdmin(e) {
    e.preventDefault();
    const btn = document.getElementById('btnAdmin');
    const msg = document.getElementById('adminMsg');
    btn.disabled = true;
    btn.innerText = 'Criando administrador...';
    msg.innerHTML = '';

    const payload = {
        action: 'create_admin',
        install_key: document.getElementById('adminKey').value,
        name: document.getElementById('adminName').value,
        email: document.getElementById('adminEmail').value,
        password: document.getElementById('adminPassword').value,
    };

    try {
        const res = await fetch('ws.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const json = await res.json();

        if (json.ok) {
            msg.innerHTML = '<div style="background:#14532d;color:#86efac;padding:10px;border-radius:6px;margin-bottom:10px;">' + json.message + '</div>';
            document.getElementById('formAdmin').style.display = 'none';
            document.getElementById('readySection').style.display = 'block';
        } else {
            msg.innerHTML = '<div class="error">' + (json.error || 'Erro ao criar administrador.') + '</div>';
            btn.disabled = false;
            btn.innerText = 'Criar Administrador';
        }
    } catch (err) {
        msg.innerHTML = '<div class="error">Erro de comunicação: ' + err.message + '</div>';
        btn.disabled = false;
        btn.innerText = 'Criar Administrador';
    }
}
</script>
</body>
</html>
