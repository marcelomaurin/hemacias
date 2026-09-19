<?php
declare(strict_types=1);

$configFile = __DIR__ . '/../config.php';
if (!is_file($configFile)) {
    http_response_code(500);
    exit('Arquivo web/config.php não encontrado. Copie config.example.php para config.php e ajuste as credenciais.');
}

$config = require $configFile;
date_default_timezone_set($config['app']['timezone'] ?? 'UTC');

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_name('hemacias_session');
    session_start();
}

function db(): PDO {
    static $pdo = null;
    global $config;

    if ($pdo === null) {
        $pdo = new PDO(
            $config['db']['dsn'],
            $config['db']['user'],
            $config['db']['password'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
    }
    return $pdo;
}

function h(?string $value): string {
    return htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function csrf_token(): string {
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function csrf_check(): void {
    $token = (string)($_POST['csrf'] ?? '');
    if (!$token || !hash_equals((string)($_SESSION['csrf'] ?? ''), $token)) {
        http_response_code(400);
        exit('CSRF inválido.');
    }
}

function current_user(): ?array {
    if (empty($_SESSION['user_id'])) {
        return null;
    }
    $st = db()->prepare('SELECT id,name,email,role,active FROM users WHERE id=?');
    $st->execute([(int)$_SESSION['user_id']]);
    $user = $st->fetch();
    return ($user && (int)$user['active'] === 1) ? $user : null;
}

function require_login(): array {
    $user = current_user();
    if (!$user) {
        header('Location: index.php?page=login');
        exit;
    }
    return $user;
}

function require_admin(array $user): void {
    if (($user['role'] ?? '') !== 'ADMIN') {
        http_response_code(403);
        exit('Acesso restrito ao administrador.');
    }
}

function audit(string $event, ?string $entityType = null, ?int $entityId = null, array $details = []): void {
    $uid = $_SESSION['user_id'] ?? null;
    $st = db()->prepare(
        'INSERT INTO audit_log(user_id,event_type,entity_type,entity_id,details_json,ip_address)
         VALUES(?,?,?,?,?,?)'
    );
    $st->execute([
        $uid ? (int)$uid : null,
        $event,
        $entityType,
        $entityId,
        $details ? json_encode($details, JSON_UNESCAPED_UNICODE) : null,
        $_SERVER['REMOTE_ADDR'] ?? null,
    ]);
}

function api_authorize(): void {
    global $config;
    $expected = (string)($config['security']['api_key'] ?? '');
    $received = (string)($_SERVER['HTTP_X_API_KEY'] ?? '');

    if ($expected === '' || $received === '' || !hash_equals($expected, $received)) {
        http_response_code(401);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'API key inválida']);
        exit;
    }
}

function json_input(): array {
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function json_response(array $data, int $status = 200): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
