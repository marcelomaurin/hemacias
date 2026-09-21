<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseWsController.php';
require_once __DIR__ . '/../Models/PatientModel.php';

final class PatientWsController extends BaseWsController {
    public static function handle(string $action): void {
        $user = self::requireAuth();

        switch ($action) {
            case 'patient_list':
                $q = trim((string)($_GET['q'] ?? $_POST['q'] ?? ''));
                $patients = PatientModel::listAll($q);
                self::success(['patients' => $patients]);
                break;

            case 'patient_get':
                $id = (int)($_GET['id'] ?? $_POST['id'] ?? 0);
                $patient = PatientModel::findById($id);
                if (!$patient) {
                    self::error('Paciente não encontrado.', 404);
                }
                self::success(['patient' => $patient]);
                break;

            case 'patient_create':
                self::checkCsrf();
                if (($user['role'] ?? '') === 'LEITURA') {
                    self::error('Perfil com permissão somente de leitura.', 403);
                }
                try {
                    $id = PatientModel::create($_POST, (int)$user['id']);
                    self::success(['id' => $id], 'Paciente cadastrado com sucesso.');
                } catch (Throwable $e) {
                    self::error($e->getMessage(), 400);
                }
                break;

            default:
                self::error('Ação de pacientes desconhecida: ' . $action, 404);
        }
    }
}
