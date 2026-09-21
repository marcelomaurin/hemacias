<?php
declare(strict_types=1);

/**
 * WebService MVC Central - Hemácias
 * Recebe ações e responde dados estruturados em JSON para a interface e clientes PHP/JS.
 */
require __DIR__ . '/lib/bootstrap.php';
require_once __DIR__ . '/lib/Controllers/BaseWsController.php';
require_once __DIR__ . '/lib/Controllers/InstallWsController.php';
require_once __DIR__ . '/lib/Controllers/VersionWsController.php';
require_once __DIR__ . '/lib/Controllers/AuthWsController.php';
require_once __DIR__ . '/lib/Controllers/PatientWsController.php';
require_once __DIR__ . '/lib/Controllers/SampleWsController.php';

// Permite leitura de corpo JSON caso enviado via fetch com application/json
$rawInput = file_get_contents('php://input');
if (!empty($rawInput)) {
    $jsonDecoded = json_decode($rawInput, true);
    if (is_array($jsonDecoded)) {
        $_POST = array_merge($_POST, $jsonDecoded);
    }
}

$action = (string)($_POST['action'] ?? $_GET['action'] ?? '');

if ($action === '') {
    http_response_code(400);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'ok' => false,
        'error' => 'Ação não especificada.',
        'available_services' => [
            'version' => ['system_version', 'check_updates'],
            'install' => ['install_status', 'auto_install', 'create_admin'],
            'auth' => ['auth_login', 'auth_logout', 'auth_me'],
            'patient' => ['patient_list', 'patient_get', 'patient_create'],
            'sample' => ['sample_list', 'sample_get', 'sample_create'],
        ],
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($action === 'debug_diagnostics') {
    $phpLint = function_exists('shell_exec') ? @shell_exec('php -l ' . escapeshellarg(__DIR__ . '/index.php') . ' 2>&1') : 'shell_exec disabled';
    $pdo = Database::pdo();
    $tables = $pdo->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
    $dbName = $pdo->query('SELECT DATABASE()')->fetchColumn();
    $indexHead = substr(file_get_contents(__DIR__ . '/index.php') ?: '', 0, 400);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'ok' => true,
        'db_name' => $dbName,
        'tables' => $tables,
        'php_lint' => $phpLint,
        'index_head' => $indexHead,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    if (in_array($action, ['system_version', 'check_updates'], true)) {
        VersionWsController::handle($action);
    } elseif (in_array($action, ['install_status', 'auto_install', 'create_admin'], true)) {
        InstallWsController::handle($action);
    } elseif (in_array($action, ['auth_login', 'auth_logout', 'auth_me'], true)) {
        AuthWsController::handle($action);
    } elseif (str_starts_with($action, 'patient_')) {
        PatientWsController::handle($action);
    } elseif (str_starts_with($action, 'sample_')) {
        SampleWsController::handle($action);
    } else {
        http_response_code(404);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'Serviço/ação não encontrada: ' . $action], JSON_UNESCAPED_UNICODE);
        exit;
    }
} catch (Throwable $e) {
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'ok' => false,
        'error' => 'Erro interno no WebService: ' . $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE);
    exit;
}
