<?php
declare(strict_types=1);

return [
    'db' => [
        'dsn' => 'mysql:host=127.0.0.1;dbname=hemacias;charset=utf8mb4',
        'user' => 'hemacias',
        'password' => 'troque-esta-senha',
    ],
    'app' => [
        'name' => 'Hemácias',
        'base_url' => 'http://localhost/hemacias/web',
        'upload_dir' => __DIR__ . '/uploads',
        'max_upload_bytes' => 10 * 1024 * 1024,
        'timezone' => 'America/Sao_Paulo',
    ],
    'security' => [
        'api_key' => 'GERE-UMA-CHAVE-LONGA-E-ALEATORIA',
        'install_key' => 'GERE-OUTRA-CHAVE-PARA-INSTALACAO',
    ],
];
