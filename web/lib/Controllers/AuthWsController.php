<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseWsController.php';
require_once __DIR__ . '/../Models/UserModel.php';

final class AuthWsController extends BaseWsController {
    public static function handle(string $action): void {
        switch ($action) {
            case 'auth_login':
                self::checkCsrf();

                $email = strtolower(trim((string)($_POST['email'] ?? '')));
                $password = (string)($_POST['password'] ?? '');

                if ($email === '' || $password === '') {
                    self::error('Informe e-mail e senha.', 400);
                }

                $user = UserModel::authenticate($email, $password);
                if (!$user) {
                    self::error('Usuário ou senha inválidos.', 401);
                }

                session_regenerate_id(true);
                $_SESSION['user_id'] = (int)$user['id'];

                self::success([
                    'user' => $user,
                    'redirect' => 'index.php',
                ], 'Login realizado com sucesso.');
                break;

            case 'auth_logout':
                $_SESSION = [];
                if (ini_get('session.use_cookies')) {
                    $params = session_get_cookie_params();
                    setcookie(
                        session_name(),
                        '',
                        time() - 42000,
                        $params['path'],
                        $params['domain'],
                        $params['secure'],
                        $params['httponly']
                    );
                }
                session_destroy();
                self::success(['redirect' => 'index.php?page=login'], 'Sessão encerrada com sucesso.');
                break;

            case 'auth_me':
                $user = self::getLoggedUser();
                if (!$user) {
                    self::success(['logged' => false, 'user' => null]);
                } else {
                    self::success(['logged' => true, 'user' => $user]);
                }
                break;

            default:
                self::error('Ação de autenticação desconhecida: ' . $action, 404);
        }
    }
}
