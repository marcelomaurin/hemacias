<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseWsController.php';
require_once __DIR__ . '/../VersionManager.php';

final class VersionWsController extends BaseWsController {
    public static function handle(string $action): void {
        switch ($action) {
            case 'system_version':
                $status = VersionManager::getStatus();
                self::success($status);
                break;

            case 'check_updates':
                self::requireAdmin();
                $status = VersionManager::getStatus();
                self::success($status);
                break;

            default:
                self::error('Ação de versionamento desconhecida: ' . $action, 404);
        }
    }
}
