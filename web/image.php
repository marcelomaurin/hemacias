<?php
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
require_login();

$id = (int)($_GET['id'] ?? 0);
$st = db()->prepare('SELECT * FROM sample_images WHERE id=?');
$st->execute([$id]);
$image = $st->fetch();

if (!$image) {
    http_response_code(404);
    exit('Imagem não encontrada.');
}

$base = realpath((string)$config['app']['upload_dir']);
$file = $base ? realpath($base . DIRECTORY_SEPARATOR . $image['stored_name']) : false;

if (!$base || !$file || !str_starts_with($file, $base . DIRECTORY_SEPARATOR) || !is_file($file)) {
    http_response_code(404);
    exit('Arquivo não encontrado.');
}

header('Content-Type: ' . $image['mime_type']);
header('Content-Length: ' . filesize($file));
header('Content-Disposition: inline; filename="' . rawurlencode($image['original_name']) . '"');
header('X-Content-Type-Options: nosniff');
readfile($file);
