<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseModel.php';

final class PatientModel extends BaseModel {
    public static function listAll(?string $query = null, int $limit = 100): array {
        if (!Database::tableExists('patients')) {
            return [];
        }
        $q = trim((string)$query);
        if ($q !== '') {
            $st = self::db()->prepare(
                'SELECT * FROM patients WHERE name LIKE ? OR external_id LIKE ? OR document LIKE ? ORDER BY created_at DESC LIMIT ' . (int)$limit
            );
            $like = '%' . $q . '%';
            $st->execute([$like, $like, $like]);
        } else {
            $st = self::db()->prepare('SELECT * FROM patients ORDER BY created_at DESC LIMIT ' . (int)$limit);
            $st->execute();
        }
        return $st->fetchAll() ?: [];
    }

    public static function findById(int $id): ?array {
        if (!Database::tableExists('patients')) {
            return null;
        }
        $st = self::db()->prepare('SELECT * FROM patients WHERE id=?');
        $st->execute([$id]);
        $row = $st->fetch();
        return $row ?: null;
    }

    public static function create(array $data, ?int $userId = null): int {
        $name = trim((string)($data['name'] ?? ''));
        if ($name === '') {
            throw new InvalidArgumentException('Nome do paciente é obrigatório.');
        }

        $st = self::db()->prepare(
            'INSERT INTO patients(external_id,name,birth_date,sex,document,notes) VALUES(?,?,?,?,?,?)'
        );
        $st->execute([
            trim((string)($data['external_id'] ?? '')) ?: null,
            $name,
            ($data['birth_date'] ?? null) ?: null,
            ($data['sex'] ?? null) ?: null,
            trim((string)($data['document'] ?? '')) ?: null,
            trim((string)($data['notes'] ?? '')) ?: null,
        ]);
        $id = (int)self::db()->lastInsertId();
        self::audit('CREATE', 'patient', $id, ['user_id' => $userId]);
        return $id;
    }
}
