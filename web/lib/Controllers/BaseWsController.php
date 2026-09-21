<?php
declare(strict_types=1);

abstract class BaseWsController {
    protected static function jsonResponse(array $data, int $status = 200): never {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    protected static function success(mixed $data = null, string $message = 'Sucesso'): never {
        $payload = ['ok' => true, 'message' => $message];
        if ($data !== null) {
            $payload['data'] = $data;
        }
        self::jsonResponse($payload, 200);
    }

    protected static function error(string $message, int $status = 400, array $extra = []): never {
        $payload = array_merge(['ok' => false, 'error' => $message], $extra);
        self::jsonResponse($payload, $status);
    }

    protected static function checkCsrf(): void {
        $token = (string)($_POST['csrf'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
        $sessionToken = (string)($_SESSION['csrf'] ?? '');
        if ($token === '' || $sessionToken === '' || !hash_equals($sessionToken, $token)) {
            self::error('Token CSRF inválido ou expirado. Recarregue a página.', 403);
        }
    }

    protected static function getLoggedUser(): ?array {
        if (empty($_SESSION['user_id'])) {
            return null;
        }
        return UserModel::findById((int)$_SESSION['user_id']);
    }

    protected static function requireAuth(): array {
        $user = self::getLoggedUser();
        if (!$user) {
            self::error('Acesso não autorizado. Faça login novamente.', 401);
        }
        return $user;
    }

    protected static function requireAdmin(): array {
        $user = self::requireAuth();
        if (($user['role'] ?? '') !== 'ADMIN') {
            self::error('Acesso restrito ao perfil de Administrador.', 403);
        }
        return $user;
    }
}
