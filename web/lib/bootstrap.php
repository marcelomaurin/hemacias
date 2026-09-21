<?php
declare(strict_types=1);

$configFile = __DIR__ . '/../config.php';
if (!is_file($configFile)) {
    http_response_code(500);
    exit('Arquivo web/config.php não encontrado. Copie config.example.php para config.php e ajuste as credenciais.');
}

// Suporta tanto "return [...]" quanto "$config = [...]" ou "$db = [...]"
unset($config, $db);
$returnedConfig = require $configFile;

if (is_array($returnedConfig)) {
    $config = $returnedConfig;
} elseif (isset($config) && is_array($config)) {
    // $config foi definido diretamente no config.php
} elseif (isset($GLOBALS['config']) && is_array($GLOBALS['config'])) {
    $config = $GLOBALS['config'];
} else {
    $config = [];
}

if (!isset($config['db']) && isset($db) && is_array($db)) {
    $config['db'] = $db;
}

if (!empty($config['app']['debug'])) {
    ini_set('display_errors', '1');
    ini_set('display_startup_errors', '1');
    error_reporting(E_ALL);
}

date_default_timezone_set($config['app']['timezone'] ?? 'America/Sao_Paulo');

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_name('hemacias_session');
    session_start();
}

// Carrega o núcleo MVC
require_once __DIR__ . '/App.php';
require_once __DIR__ . '/Database.php';
require_once __DIR__ . '/VersionManager.php';
require_once __DIR__ . '/Installer.php';
require_once __DIR__ . '/Models/BaseModel.php';
require_once __DIR__ . '/Models/VersionModel.php';
require_once __DIR__ . '/Models/UserModel.php';
require_once __DIR__ . '/Models/PatientModel.php';
require_once __DIR__ . '/Models/SampleModel.php';
require_once __DIR__ . '/Models/ParamModel.php';

/**
 * Retorna o PDO seguro da classe Database (mantido para compatibilidade).
 */
function db(): PDO {
    return Database::pdo();
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
    $token = (string)($_POST['csrf'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
    if (!$token || !hash_equals((string)($_SESSION['csrf'] ?? ''), $token)) {
        http_response_code(400);
        exit('CSRF inválido ou expirado.');
    }
}

/**
 * Retorna o usuário logado de forma segura sem quebrar caso o banco esteja indisponível.
 */
function current_user(): ?array {
    if (empty($_SESSION['user_id'])) {
        return null;
    }
    try {
        return UserModel::findById((int)$_SESSION['user_id']);
    } catch (Throwable $e) {
        error_log('Erro ao carregar current_user: ' . $e->getMessage());
        return null;
    }
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
    try {
        if (!Database::tableExists('audit_log')) {
            return;
        }
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
    } catch (Throwable) {
    }
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

// Auto-verificação do banco: se as tabelas não foram criadas, cria automaticamente
try {
    Installer::ensureInstalled();
} catch (Throwable $e) {
    error_log('Erro no auto-instalador de banco: ' . $e->getMessage());
}
