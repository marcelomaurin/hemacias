<?php
declare(strict_types=1);

require_once __DIR__ . '/BaseWsController.php';
require_once __DIR__ . '/../Models/SampleModel.php';

final class SampleWsController extends BaseWsController {
    public static function handle(string $action): void {
        $user = self::requireAuth();

        switch ($action) {
            case 'sample_list':
                $patientId = (int)($_GET['patient_id'] ?? $_POST['patient_id'] ?? 0);
                if ($patientId < 1) {
                    self::error('ID do paciente obrigatório.', 400);
                }
                $samples = SampleModel::listByPatient($patientId);
                self::success(['samples' => $samples]);
                break;

            case 'sample_get':
                $id = (int)($_GET['id'] ?? $_POST['id'] ?? 0);
                $sample = SampleModel::findById($id);
                if (!$sample) {
                    self::error('Amostra não encontrada.', 404);
                }
                self::success(['sample' => $sample]);
                break;

            case 'sample_create':
                self::checkCsrf();
                if (($user['role'] ?? '') === 'LEITURA') {
                    self::error('Perfil com permissão somente de leitura.', 403);
                }
                try {
                    $id = SampleModel::create($_POST, (int)$user['id']);
                    self::success(['id' => $id], 'Amostra criada com sucesso.');
                } catch (Throwable $e) {
                    self::error($e->getMessage(), 400);
                }
                break;

            default:
                self::error('Ação de amostras desconhecida: ' . $action, 404);
        }
    }
}
