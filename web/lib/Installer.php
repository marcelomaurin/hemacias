<?php
declare(strict_types=1);

require_once __DIR__ . '/App.php';
require_once __DIR__ . '/Database.php';
require_once __DIR__ . '/VersionManager.php';
require_once __DIR__ . '/Models/UserModel.php';
require_once __DIR__ . '/Models/VersionModel.php';
require_once __DIR__ . '/Models/ParamModel.php';

final class Installer {
    /**
     * Retorna o diagnóstico completo para o instalador.
     */
    public static function getStatus(): array {
        $conn = Database::testConnection();
        if (!$conn['ok']) {
            return [
                'ok' => false,
                'connected' => false,
                'installed' => false,
                'has_admin' => false,
                'error' => $conn['message'],
            ];
        }

        $hasUsersTable = Database::tableExists('users');
        $hasVersionTable = Database::tableExists('system_version');
        $hasAdmin = $hasUsersTable ? UserModel::hasAdmin() : false;
        $versionStatus = VersionManager::getStatus();

        return [
            'ok' => true,
            'connected' => true,
            'installed' => $hasUsersTable && $hasVersionTable,
            'has_admin' => $hasAdmin,
            'users_count' => $hasUsersTable ? UserModel::count() : 0,
            'version_status' => $versionStatus,
            'mysql_version' => $conn['mysql_version'],
        ];
    }

    /**
     * Executa a auto-instalação completa:
     * 1. Cria tabelas de controle de versão (system_version, schema_migrations)
     * 2. Se a tabela users não existir, executa o schema base
     * 3. Executa todas as migrações pendentes em migrations/*.sql
     * 4. Atualiza o registro de versão
     */
    public static function runAutoInstall(): array {
        $conn = Database::testConnection();
        if (!$conn['ok']) {
            return [
                'ok' => false,
                'error' => 'Não foi possível conectar ao banco de dados: ' . $conn['message'],
            ];
        }

        $log = [];

        // 1. Inicializa tabelas de versionamento
        VersionModel::initTables();
        $log[] = 'Tabelas de controle de versão inicializadas.';

        // 2. Se as tabelas base não existem, executa schema.sql sanitizado
        if (!Database::tableExists('users')) {
            $schemaFile = __DIR__ . '/../schema.sql';
            if (is_file($schemaFile)) {
                $sql = file_get_contents($schemaFile) ?: '';
                $res = Database::executeSqlScript($sql);
                $log[] = sprintf('Schema base executado (%d comandos aplicados).', $res['executed']);
                if (!empty($res['errors'])) {
                    $log[] = sprintf('Avisos no schema base: %d declarações com alertas.', count($res['errors']));
                }
            } else {
                return [
                    'ok' => false,
                    'error' => 'Arquivo schema.sql não foi encontrado.',
                ];
            }
        } else {
            $log[] = 'Tabelas base já detectadas no banco de dados.';
        }

        // 3. Executa migrações pendentes
        $migrationFiles = VersionManager::getMigrationFiles();
        $applied = VersionModel::getAppliedMigrations();
        $migratedCount = 0;

        foreach ($migrationFiles as $file) {
            if (in_array($file, $applied, true)) {
                continue;
            }

            $filePath = __DIR__ . '/../migrations/' . $file;
            $sql = file_get_contents($filePath) ?: '';
            $res = Database::executeSqlScript($sql);
            VersionModel::recordMigration($file);
            $migratedCount++;
            $log[] = sprintf('Migração %s aplicada com sucesso (%d comandos).', $file, $res['executed']);
        }

        // 4. Grava a versão final do sistema
        VersionModel::setVersion(App::VERSION, App::SCHEMA_TARGET_VERSION, 'Instalação/migração automática concluída');
        $log[] = sprintf('Versão do sistema registrada: %s (Schema v%d).', App::VERSION, App::SCHEMA_TARGET_VERSION);

        return [
            'ok' => true,
            'message' => 'Auto-instalação concluída com sucesso!',
            'log' => $log,
            'migrated_count' => $migratedCount,
            'has_admin' => UserModel::hasAdmin(),
        ];
    }

    /**
     * Cria o primeiro administrador validando a chave de instalação.
     */
    public static function createFirstAdmin(string $name, string $email, string $password, string $installKey): array {
        global $config;

        $expectedKey = (string)($config['security']['install_key'] ?? '');
        if ($expectedKey === '' || !hash_equals($expectedKey, $installKey)) {
            return ['ok' => false, 'error' => 'Chave de instalação inválida.'];
        }

        if (UserModel::hasAdmin()) {
            return ['ok' => false, 'error' => 'Já existe um administrador cadastrado no sistema.'];
        }

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return ['ok' => false, 'error' => 'E-mail inválido.'];
        }

        if (strlen($password) < 10) {
            return ['ok' => false, 'error' => 'A senha deve ter pelo menos 10 caracteres.'];
        }

        try {
            $userId = UserModel::createAdmin($name, $email, $password);
            return [
                'ok' => true,
                'user_id' => $userId,
                'message' => 'Administrador inicial criado com sucesso!',
            ];
        } catch (Throwable $e) {
            return [
                'ok' => false,
                'error' => 'Falha ao cadastrar administrador: ' . $e->getMessage(),
            ];
        }
    }

    /**
     * Verifica se as tabelas existem. Se não existirem, cria automaticamente na hora.
     */
    public static function ensureInstalled(): void {
        $conn = Database::testConnection();
        if (!$conn['ok']) {
            return;
        }

        // Garante a tabela params com VERSAO = 1.0
        if (!Database::tableExists('params')) {
            ParamModel::initTable();
        }

        // Se a tabela users não existe, roda o auto-instalador completo
        if (!Database::tableExists('users')) {
            self::runAutoInstall();
        }
    }

}
