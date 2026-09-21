<?php
declare(strict_types=1);

abstract class BaseModel {
    protected static function db(): PDO {
        return Database::pdo();
    }

    protected static function audit(string $event, ?string $entityType = null, ?int $entityId = null, array $details = []): void {
        try {
            if (!Database::tableExists('audit_log')) {
                return;
            }
            $uid = $_SESSION['user_id'] ?? null;
            $st = self::db()->prepare(
                'INSERT INTO audit_log(user_id,event_type,entity_type,entity_id,details_json,ip_address)
                 VALUES(?,?,?,?,?,?)'
            );
            $st->execute([
                $uid ? (int)$uid : null,
                $event,
                $entityType,
                $entityId,
                $details ? json_encode($details, JSON_UNESCAPED_UNICODE) : null,
                $_SERVER['REMOTE_ADDR'] ?? null,
            ]);
        } catch (Throwable) {
            // Não quebra a transação caso a auditoria falhe
        }
    }
}
