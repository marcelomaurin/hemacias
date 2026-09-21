<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseModel.php';

final class ParamModel extends BaseModel {
    /**
     * Cria a tabela params caso não exista e insere a chave VERSAO com valor inicial 1.0
     */
    public static function initTable(): void {
        $pdo = self::db();
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS params (
                `key` VARCHAR(80) NOT NULL PRIMARY KEY,
                `value` TEXT NULL,
                `description` VARCHAR(255) NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB;
        ");

        $st = $pdo->prepare("
            INSERT IGNORE INTO params(`key`, `value`, `description`)
            VALUES('VERSAO', '1.0', 'Versão atual do sistema')
        ");
        $st->execute();
    }

    /**
     * Retorna o valor de uma chave ou o padrão
     */
    public static function get(string $key, ?string $default = null): ?string {
        if (!Database::tableExists('params')) {
            return $default;
        }
        $st = self::db()->prepare("SELECT `value` FROM params WHERE `key` = ?");
        $st->execute([$key]);
        $val = $st->fetchColumn();
        return $val !== false ? (string)$val : $default;
    }

    /**
     * Grava ou atualiza uma chave
     */
    public static function set(string $key, string $value, ?string $description = null): void {
        self::initTable();
        $st = self::db()->prepare("
            INSERT INTO params(`key`, `value`, `description`)
            VALUES(?,?,?)
            ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `updated_at` = NOW()
        ");
        $st->execute([$key, $value, $description]);
    }

    /**
     * Retorna a versão gravada no banco (padrão 1.0)
     */
    public static function getVersion(): string {
        return self::get('VERSAO', '1.0') ?? '1.0';
    }
}
