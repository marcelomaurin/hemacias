<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseModel.php';

final class SampleModel extends BaseModel {
    public static function listByPatient(int $patientId): array {
        if (!Database::tableExists('samples')) {
            return [];
        }
        $st = self::db()->prepare(
            'SELECT s.*, cp.name AS protocol_name
             FROM samples s
             LEFT JOIN count_protocols cp ON cp.id = s.protocol_id
             WHERE s.patient_id = ?
             ORDER BY s.created_at DESC'
        );
        $st->execute([$patientId]);
        return $st->fetchAll() ?: [];
    }

    public static function findById(int $id): ?array {
        if (!Database::tableExists('samples')) {
            return null;
        }
        $st = self::db()->prepare(
            'SELECT s.*, p.name AS patient_name, p.external_id AS patient_external_id, cp.name AS protocol_name
             FROM samples s
             JOIN patients p ON p.id = s.patient_id
             LEFT JOIN count_protocols cp ON cp.id = s.protocol_id
             WHERE s.id = ?'
        );
        $st->execute([$id]);
        $row = $st->fetch();
        return $row ?: null;
    }

    public static function create(array $data, ?int $userId = null): int {
        $patientId = (int)($data['patient_id'] ?? 0);
        $code = trim((string)($data['sample_code'] ?? ''));
        if ($patientId < 1 || $code === '') {
            throw new InvalidArgumentException('Paciente e código da amostra são obrigatórios.');
        }

        $protocolId = (int)($data['protocol_id'] ?? 0);
        $st = self::db()->prepare(
            'INSERT INTO samples(patient_id, protocol_id, sample_code, collected_at, sample_type, notes, created_by)
             VALUES(?,?,?,?,?,?,?)'
        );
        $st->execute([
            $patientId,
            $protocolId > 0 ? $protocolId : null,
            $code,
            ($data['collected_at'] ?? null) ?: null,
            ($data['sample_type'] ?? 'sangue') ?: 'sangue',
            trim((string)($data['notes'] ?? '')) ?: null,
            $userId,
        ]);
        $id = (int)self::db()->lastInsertId();
        self::audit('CREATE', 'sample', $id, ['user_id' => $userId]);
        return $id;
    }
}
