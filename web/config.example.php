<?php
declare(strict_types=1);

return [
    'db' => [
        // Em hospedagens compartilhadas como Hostinger, use host=localhost e adicione o prefixo da conta no dbname e user:
        // Exemplo: 'mysql:host=localhost;dbname=u123456789_hemacias;charset=utf8mb4'
        'dsn' => 'mysql:host=localhost;dbname=hemacias;charset=utf8mb4',
        'user' => 'hemacias',
        'password' => 'troque-esta-senha',
    ],
    'app' => [
        'name' => 'Hemácias',
        'base_url' => 'http://localhost/hemacias/web',
        'upload_dir' => __DIR__ . '/uploads',
        'max_upload_bytes' => 10 * 1024 * 1024,
        'timezone' => 'America/Sao_Paulo',
        'debug' => false,
    ],
    'security' => [
        'api_key' => 'GERE-UMA-CHAVE-LONGA-E-ALEATORIA',
        'install_key' => 'GERE-OUTRA-CHAVE-PARA-INSTALACAO',
    ],
];
