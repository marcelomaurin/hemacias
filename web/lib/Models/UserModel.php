<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseModel.php';

final class UserModel extends BaseModel {
    public static function findById(int $id): ?array {
        if (!Database::tableExists('users')) {
            return null;
        }
        $st = self::db()->prepare('SELECT id,name,email,role,active,created_at FROM users WHERE id=?');
        $st->execute([$id]);
        $row = $st->fetch();
        return ($row && (int)$row['active'] === 1) ? $row : null;
    }

    public static function findByEmail(string $email): ?array {
        if (!Database::tableExists('users')) {
            return null;
        }
        $st = self::db()->prepare('SELECT * FROM users WHERE email=?');
        $st->execute([strtolower(trim($email))]);
        $row = $st->fetch();
        return $row ?: null;
    }

    public static function authenticate(string $email, string $password): ?array {
        $user = self::findByEmail($email);
        if (!$user || (int)$user['active'] !== 1) {
            return null;
        }
        if (!password_verify($password, $user['password_hash'])) {
            return null;
        }
        return [
            'id' => (int)$user['id'],
            'name' => (string)$user['name'],
            'email' => (string)$user['email'],
            'role' => (string)$user['role'],
        ];
    }

    public static function count(): int {
        if (!Database::tableExists('users')) {
            return 0;
        }
        return (int)self::db()->query('SELECT COUNT(*) FROM users')->fetchColumn();
    }

    public static function hasAdmin(): bool {
        if (!Database::tableExists('users')) {
            return false;
        }
        $st = self::db()->query("SELECT COUNT(*) FROM users WHERE role='ADMIN' AND active=1");
        return ((int)$st->fetchColumn()) > 0;
    }

    public static function createAdmin(string $name, string $email, string $password): int {
        $st = self::db()->prepare(
            "INSERT INTO users(name,email,password_hash,role,active) VALUES(?,?,?,'ADMIN',1)"
        );
        $st->execute([
            trim($name),
            strtolower(trim($email)),
            password_hash($password, PASSWORD_DEFAULT),
        ]);
        $id = (int)self::db()->lastInsertId();
        self::audit('CREATE', 'user', $id, ['role' => 'ADMIN', 'auto_install' => true]);
        return $id;
    }

    public static function create(array $data, ?int $createdBy = null): int {
        $st = self::db()->prepare(
            'INSERT INTO users(name,email,password_hash,role,active) VALUES(?,?,?,?,1)'
        );
        $st->execute([
            trim((string)$data['name']),
            strtolower(trim((string)$data['email'])),
            password_hash((string)$data['password'], PASSWORD_DEFAULT),
            (string)($data['role'] ?? 'OPERADOR'),
        ]);
        $id = (int)self::db()->lastInsertId();
        self::audit('CREATE', 'user', $id, ['created_by' => $createdBy]);
        return $id;
    }

    public static function listAll(): array {
        if (!Database::tableExists('users')) {
            return [];
        }
        $st = self::db()->query('SELECT id,name,email,role,active,created_at FROM users ORDER BY name ASC');
        return $st->fetchAll() ?: [];
    }
}
