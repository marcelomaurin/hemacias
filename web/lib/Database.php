<?php
declare(strict_types=1);

final class Database {
    private static ?PDO $pdo = null;

    /**
     * Extrai a configuração de banco de forma flexível suportando múltiplos formatos.
     */
    public static function getConfig(): array {
        global $config;

        $dbConf = [];
        if (isset($config['db']) && is_array($config['db'])) {
            $dbConf = $config['db'];
        } elseif (isset($GLOBALS['config']['db']) && is_array($GLOBALS['config']['db'])) {
            $dbConf = $GLOBALS['config']['db'];
        } elseif (isset($GLOBALS['db']) && is_array($GLOBALS['db'])) {
            $dbConf = $GLOBALS['db'];
        }

        return $dbConf;
    }

    /**
     * Retorna a instância única do PDO com tratamento seguro de erros.
     */
    public static function pdo(): PDO {
        if (self::$pdo === null) {
            $dbConf = self::getConfig();
            if (empty($dbConf)) {
                throw new RuntimeException('Configurações de banco de dados não encontradas no config.php. Verifique se o array contém as chaves db (dsn, user, password).');
            }

            $dsn = $dbConf['dsn'] ?? null;
            if (!$dsn) {
                $host = $dbConf['host'] ?? 'localhost';
                $dbname = $dbConf['database'] ?? $dbConf['dbname'] ?? 'hemacias';
                $charset = $dbConf['charset'] ?? 'utf8mb4';
                $dsn = "mysql:host={$host};dbname={$dbname};charset={$charset}";
            }
            $user = (string)($dbConf['user'] ?? $dbConf['username'] ?? '');
            $password = (string)($dbConf['password'] ?? $dbConf['pass'] ?? '');

            try {
                self::$pdo = new PDO(
                    $dsn,
                    $user,
                    $password,
                    [
                        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                        PDO::ATTR_EMULATE_PREPARES => false,
                        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4",
                    ]
                );
            } catch (PDOException $e) {
                $errorMsg = 'Falha de conexão com o banco de dados MySQL: ' . $e->getMessage();
                error_log($errorMsg);
                throw new RuntimeException($errorMsg, (int)$e->getCode(), $e);
            }
        }
        return self::$pdo;
    }

    /**
     * Testa a conectividade com o banco sem disparar fatal error não capturado.
     */
    public static function testConnection(): array {
        try {
            $pdo = self::pdo();
            $version = $pdo->query('SELECT VERSION()')->fetchColumn();
            return [
                'ok' => true,
                'mysql_version' => (string)$version,
                'message' => 'Conexão com MySQL estabelecida com sucesso.',
            ];
        } catch (Throwable $e) {
            return [
                'ok' => false,
                'mysql_version' => null,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Verifica se uma tabela existe no banco de dados atual.
     */
    public static function tableExists(string $tableName): bool {
        try {
            $st = self::pdo()->prepare('SHOW TABLES LIKE ?');
            $st->execute([$tableName]);
            return (bool)$st->fetch();
        } catch (Throwable) {
            return false;
        }
    }

    /**
     * Executa comandos SQL sanitizados (removendo USE e CREATE DATABASE para evitar erros em hospedagens).
     */
    public static function executeSqlScript(string $sql): array {
        $pdo = self::pdo();
        $executed = 0;
        $errors = [];

        // Remove comentários
        $sql = preg_replace('/--.*$/m', '', $sql);
        $sql = preg_replace('/\/\*.*?\*\//s', '', $sql);

        $statements = preg_split('/;\s*$/m', $sql);

        foreach ($statements as $stmt) {
            $stmt = trim($stmt);
            if ($stmt === '') {
                continue;
            }

            // Ignora comandos proibidos em hospedagens compartilhadas
            if (preg_match('/^\s*(CREATE\s+DATABASE|USE\s+)/i', $stmt)) {
                continue;
            }

            try {
                $pdo->exec($stmt);
                $executed++;
            } catch (PDOException $e) {
                $code = (int)($e->errorInfo[1] ?? 0);
                if (!in_array($code, [1050, 1060, 1061], true)) {
                    $errors[] = [
                        'statement' => substr($stmt, 0, 120) . '...',
                        'error' => $e->getMessage(),
                        'code' => $code,
                    ];
                }
            }
        }

        return [
            'executed' => $executed,
            'errors' => $errors,
        ];
    }
}
