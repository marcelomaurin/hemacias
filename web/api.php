<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
api_authorize();

$action = (string)($_GET['action'] ?? $_POST['action'] ?? '');

try {
    if ($action === 'patient_upsert') {
        $d = json_input();
        $name = trim((string)($d['name'] ?? ''));
        if ($name === '') json_response(['ok'=>false,'error'=>'name obrigatório'], 422);

        $externalId = trim((string)($d['external_id'] ?? ''));
        $pdo = db();

        if ($externalId !== '') {
            $st = $pdo->prepare('SELECT id FROM patients WHERE external_id=?');
            $st->execute([$externalId]);
            $id = $st->fetchColumn();
            if ($id) {
                $st = $pdo->prepare('UPDATE patients SET name=?,birth_date=?,sex=?,document=?,notes=? WHERE id=?');
                $st->execute([
                    $name, $d['birth_date'] ?? null, $d['sex'] ?? null,
                    $d['document'] ?? null, $d['notes'] ?? null, (int)$id
                ]);
                json_response(['ok'=>true,'patient_id'=>(int)$id,'updated'=>true]);
            }
        }

        $st = $pdo->prepare('INSERT INTO patients(external_id,name,birth_date,sex,document,notes) VALUES(?,?,?,?,?,?)');
        $st->execute([
            $externalId !== '' ? $externalId : null,
            $name, $d['birth_date'] ?? null, $d['sex'] ?? null,
            $d['document'] ?? null, $d['notes'] ?? null
        ]);
        json_response(['ok'=>true,'patient_id'=>(int)$pdo->lastInsertId(),'updated'=>false]);
    }

    if ($action === 'sample_create') {
        $d = json_input();
        $patientId = (int)($d['patient_id'] ?? 0);
        $code = trim((string)($d['sample_code'] ?? ''));
        if ($patientId < 1 || $code === '') {
            json_response(['ok'=>false,'error'=>'patient_id e sample_code obrigatórios'], 422);
        }

        $pdo = db();
        $st = $pdo->prepare('SELECT id FROM samples WHERE patient_id=? AND sample_code=?');
        $st->execute([$patientId, $code]);
        $id = $st->fetchColumn();
        if ($id) json_response(['ok'=>true,'sample_id'=>(int)$id,'existing'=>true]);

        $st = $pdo->prepare(
            'INSERT INTO samples(patient_id,sample_code,collected_at,sample_type,notes)
             VALUES(?,?,?,?,?)'
        );
        $st->execute([
            $patientId, $code, $d['collected_at'] ?? null,
            $d['sample_type'] ?? 'sangue', $d['notes'] ?? null
        ]);
        json_response(['ok'=>true,'sample_id'=>(int)$pdo->lastInsertId(),'existing'=>false]);
    }

    if ($action === 'count_create') {
        $pdo = db();
        $payload = $_POST['payload'] ?? '';
        $d = json_decode((string)$payload, true);
        if (!is_array($d)) json_response(['ok'=>false,'error'=>'payload JSON inválido'], 422);

        $sampleId = (int)($d['sample_id'] ?? 0);
        if ($sampleId < 1) json_response(['ok'=>false,'error'=>'sample_id obrigatório'], 422);

        $pdo->beginTransaction();

        $st = $pdo->prepare(
            'INSERT INTO counts(sample_id,method,algorithm_version,scale_label,magnification,pixel_size_um,
             focus_score,image_quality,total_cells,notes,source)
             VALUES(?,?,?,?,?,?,?,?,?,?,\'PYTHON\')'
        );
        $st->execute([
            $sampleId,
            $d['method'] ?? 'opencv-hough',
            $d['algorithm_version'] ?? null,
            $d['scale_label'] ?? null,
            $d['magnification'] ?? null,
            $d['pixel_size_um'] ?? null,
            $d['focus_score'] ?? null,
            $d['image_quality'] ?? null,
            $d['total_cells'] ?? null,
            $d['notes'] ?? null,
        ]);
        $countId = (int)$pdo->lastInsertId();

        $components = is_array($d['components'] ?? null) ? $d['components'] : [];
        $stComp = $pdo->prepare(
            'INSERT INTO count_components(count_id,component_code,component_name,quantity,unit,confidence,metadata_json)
             VALUES(?,?,?,?,?,?,?)'
        );
        foreach ($components as $component) {
            $stComp->execute([
                $countId,
                (string)($component['code'] ?? 'outro'),
                (string)($component['name'] ?? 'Outro'),
                max(0, (int)($component['quantity'] ?? 0)),
                (string)($component['unit'] ?? 'células/campo'),
                isset($component['confidence']) ? (float)$component['confidence'] : null,
                isset($component['metadata']) ? json_encode($component['metadata'], JSON_UNESCAPED_UNICODE) : null,
            ]);
        }

        $imageId = null;
        if (!empty($_FILES['image']) && is_uploaded_file($_FILES['image']['tmp_name'])) {
            $file = $_FILES['image'];
            if ((int)$file['size'] > (int)$config['app']['max_upload_bytes']) {
                throw new RuntimeException('Imagem excede o limite configurado.');
            }

            $finfo = new finfo(FILEINFO_MIME_TYPE);
            $mime = $finfo->file($file['tmp_name']);
            $allowed = ['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp'];
            if (!isset($allowed[$mime])) throw new RuntimeException('Formato de imagem não permitido.');

            $dir = rtrim((string)$config['app']['upload_dir'], '/\\') . '/' . date('Y/m');
            if (!is_dir($dir) && !mkdir($dir, 0770, true) && !is_dir($dir)) {
                throw new RuntimeException('Não foi possível criar diretório de upload.');
            }

            $stored = bin2hex(random_bytes(16)) . '.' . $allowed[$mime];
            $dest = $dir . '/' . $stored;
            if (!move_uploaded_file($file['tmp_name'], $dest)) {
                throw new RuntimeException('Falha ao armazenar imagem.');
            }

            [$width, $height] = getimagesize($dest) ?: [null, null];
            $relative = date('Y/m') . '/' . $stored;
            $sha = hash_file('sha256', $dest);

            $stImg = $pdo->prepare(
                'INSERT INTO sample_images(sample_id,field_id,count_id,original_name,stored_name,mime_type,file_size,sha256,
                 width_px,height_px,scale_label,magnification)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?)'
            );
            $stImg->execute([
                $sampleId, $fieldId, $countId, basename((string)$file['name']), $relative, $mime,
                (int)$file['size'], $sha, $width, $height,
                $d['scale_label'] ?? null, $d['magnification'] ?? null
            ]);
            $imageId = (int)$pdo->lastInsertId();
        }

        $pdo->commit();
        json_response(['ok'=>true,'count_id'=>$countId,'image_id'=>$imageId,'field_id'=>$fieldId,'field_no'=>$fieldNo]);
    }

    if ($action === 'patient_search') {
        $q = trim((string)($_GET['q'] ?? ''));
        $st = db()->prepare(
            'SELECT id,external_id,name,birth_date FROM patients
             WHERE name LIKE ? OR external_id LIKE ? ORDER BY name LIMIT 20'
        );
        $like = '%' . $q . '%';
        $st->execute([$like, $like]);
        json_response(['ok'=>true,'patients'=>$st->fetchAll()]);
    }

    json_response(['ok'=>false,'error'=>'Ação não encontrada'], 404);
} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    json_response(['ok'=>false,'error'=>$e->getMessage()], 500);
}
