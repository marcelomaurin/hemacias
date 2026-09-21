<?php
declare(strict_types=1);

final class App {
    public const DEFAULT_VERSION = '1.0';
    public const SCHEMA_TARGET_VERSION = 10;
    public const NAME = 'Hemácias';

    /**
     * Retorna a versão atual do sistema a partir da tabela params (chave VERSAO, padrão 1.0)
     */
    public static function getVersion(): string {
        if (class_exists('ParamModel')) {
            try {
                return ParamModel::getVersion();
            } catch (Throwable) {
            }
        }
        return self::DEFAULT_VERSION;
    }

    /**
     * Informações consolidadas do sistema
     */
    public static function getInfo(): array {
        return [
            'app_name' => self::NAME,
            'app_version' => self::getVersion(),
            'schema_target_version' => self::SCHEMA_TARGET_VERSION,
            'php_version' => PHP_VERSION,
            'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'CLI',
            'timestamp' => date('Y-m-d H:i:s'),
        ];
    }
}
