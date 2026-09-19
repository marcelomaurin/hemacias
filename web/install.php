<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

$count = (int)db()->query('SELECT COUNT(*) FROM users')->fetchColumn();
if ($count > 0) {
    exit('Já existe usuário cadastrado. Remova este arquivo ou mantenha-o inacessível em produção.');
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $installKey = (string)($_POST['install_key'] ?? '');
    if (!hash_equals((string)$config['security']['install_key'], $installKey)) {
        $error = 'Chave de instalação inválida.';
    } elseif (!filter_var($_POST['email'] ?? '', FILTER_VALIDATE_EMAIL)) {
        $error = 'E-mail inválido.';
    } elseif (strlen((string)($_POST['password'] ?? '')) < 10) {
        $error = 'A senha deve ter pelo menos 10 caracteres.';
    } else {
        $st = db()->prepare('INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,\'ADMIN\')');
        $st->execute([
            trim((string)$_POST['name']),
            strtolower(trim((string)$_POST['email'])),
            password_hash((string)$_POST['password'], PASSWORD_DEFAULT),
        ]);
        header('Location: index.php?page=login');
        exit;
    }
}
?><!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Instalação - Hemácias</title>
<link rel="stylesheet" href="assets/style.css"></head><body><main class="narrow">
<h1>Primeiro administrador</h1>
<?php if ($error): ?><div class="error"><?=h($error)?></div><?php endif; ?>
<form method="post" class="card">
<label>Chave de instalação<input type="password" name="install_key" required></label>
<label>Nome<input name="name" required></label>
<label>E-mail<input type="email" name="email" required></label>
<label>Senha<input type="password" name="password" minlength="10" required></label>
<button>Criar administrador</button>
</form></main></body></html>
