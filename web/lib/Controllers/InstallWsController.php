<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseWsController.php';
require_once __DIR__ . '/../Installer.php';

final class InstallWsController extends BaseWsController {
    public static function handle(string $action): void {
        switch ($action) {
            case 'install_status':
                $status = Installer::getStatus();
                self::success($status);
                break;

            case 'auto_install':
                $res = Installer::runAutoInstall();
                if ($res['ok']) {
                    self::success($res, $res['message']);
                } else {
                    self::error($res['error'] ?? 'Falha na auto-instalação.', 500, ['log' => $res['log'] ?? []]);
                }
                break;

            case 'create_admin':
                $name = trim((string)($_POST['name'] ?? ''));
                $email = trim((string)($_POST['email'] ?? ''));
                $password = (string)($_POST['password'] ?? '');
                $installKey = (string)($_POST['install_key'] ?? '');

                $res = Installer::createFirstAdmin($name, $email, $password, $installKey);
                if ($res['ok']) {
                    self::success($res, $res['message']);
                } else {
                    self::error($res['error'] ?? 'Falha ao criar administrador.', 400);
                }
                break;

            default:
                self::error('Ação de instalação desconhecida: ' . $action, 404);
        }
    }
}
