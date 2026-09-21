<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseModel.php';

final class VersionModel extends BaseModel {
    public static function initTables(): void {
        $pdo = self::db();
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS system_version (
                id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                app_version VARCHAR(30) NOT NULL,
                schema_version INT UNSIGNED NOT NULL DEFAULT 1,
                notes VARCHAR(255) NULL,
                installed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB;
        ");

        $pdo->exec("
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                migration_file VARCHAR(120) NOT NULL UNIQUE,
                batch INT UNSIGNED NOT NULL DEFAULT 1,
                applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB;
        ");
    }

    public static function getLatest(): ?array {
        if (!Database::tableExists('system_version')) {
            return null;
        }
        $st = self::db()->query('SELECT * FROM system_version ORDER BY id DESC LIMIT 1');
        $row = $st->fetch();
        return $row ?: null;
    }

    public static function setVersion(string $appVersion, int $schemaVersion, ?string $notes = null): void {
        self::initTables();
        $existing = self::getLatest();
        if ($existing) {
            $st = self::db()->prepare(
                'UPDATE system_version SET app_version=?, schema_version=?, notes=?, updated_at=NOW() WHERE id=?'
            );
            $st->execute([$appVersion, $schemaVersion, $notes, $existing['id']]);
        } else {
            $st = self::db()->prepare(
                'INSERT INTO system_version(app_version, schema_version, notes) VALUES(?,?,?)'
            );
            $st->execute([$appVersion, $schemaVersion, $notes]);
        }
    }

    public static function getAppliedMigrations(): array {
        if (!Database::tableExists('schema_migrations')) {
            return [];
        }
        $st = self::db()->query('SELECT migration_file FROM schema_migrations ORDER BY id ASC');
        return $st->fetchAll(PDO::FETCH_COLUMN) ?: [];
    }

    public static function recordMigration(string $file, int $batch = 1): void {
        self::initTables();
        $st = self::db()->prepare(
            'INSERT IGNORE INTO schema_migrations(migration_file, batch) VALUES(?,?)'
        );
        $st->execute([$file, $batch]);
    }
}
