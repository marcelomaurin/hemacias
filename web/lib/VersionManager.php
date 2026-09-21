<?php
declare(strict_types=1);

require_once __DIR__ . '/App.php';
require_once __DIR__ . '/Database.php';
require_once __DIR__ . '/Models/VersionModel.php';

final class VersionManager {
    /**
     * Retorna o status consolidado da versão da aplicação e do schema.
     */
    public static function getStatus(): array {
        $appVersion = App::VERSION;
        $targetSchema = App::SCHEMA_TARGET_VERSION;

        $dbTest = Database::testConnection();
        if (!$dbTest['ok']) {
            return [
                'ok' => false,
                'connected' => false,
                'app_version' => $appVersion,
                'current_schema' => 0,
                'target_schema' => $targetSchema,
                'is_up_to_date' => false,
                'pending_migrations' => [],
                'error' => $dbTest['message'],
            ];
        }

        $versionRow = VersionModel::getLatest();
        $currentSchema = $versionRow ? (int)$versionRow['schema_version'] : 0;
        $appliedMigrations = VersionModel::getAppliedMigrations();
        $allMigrationFiles = self::getMigrationFiles();

        $pending = [];
        foreach ($allMigrationFiles as $file) {
            if (!in_array($file, $appliedMigrations, true)) {
                $pending[] = $file;
            }
        }

        return [
            'ok' => true,
            'connected' => true,
            'app_name' => App::NAME,
            'app_version' => $appVersion,
            'current_schema' => $currentSchema,
            'target_schema' => $targetSchema,
            'is_up_to_date' => ($currentSchema >= $targetSchema) && empty($pending),
            'applied_migrations_count' => count($appliedMigrations),
            'pending_migrations' => $pending,
            'last_update' => $versionRow['updated_at'] ?? $versionRow['installed_at'] ?? null,
        ];
    }

    /**
     * Lista todos os arquivos de migração existentes em migrations/
     */
    public static function getMigrationFiles(): array {
        $dir = __DIR__ . '/../migrations';
        if (!is_dir($dir)) {
            return [];
        }
        $files = scandir($dir);
        $migrations = [];
        foreach ($files as $f) {
            if (str_ends_with($f, '.sql')) {
                $migrations[] = $f;
            }
        }
        sort($migrations, SORT_NATURAL);
        return $migrations;
    }
}
