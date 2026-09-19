# Gerenciador Web

Requisitos:

- PHP 8.1+
- MySQL 5.7+/8.0+
- extensões PDO MySQL e FileInfo
- servidor HTTPS em produção

## Instalação

1. Importe `schema.sql` no MySQL.
2. Copie `config.example.php` para `config.php`.
3. Configure banco, `api_key`, `install_key` e diretório de upload.
4. Garanta permissão de escrita para `web/uploads/` pelo usuário do servidor web.
5. Abra `install.php` e crie o primeiro administrador.
6. Após a instalação, restrinja ou remova `install.php` no servidor.
7. Acesse `index.php`.

Nunca versione `config.php`: ele contém credenciais e chaves.

## Estrutura de dados

Paciente -> Amostras -> Contagens -> Componentes.

Uma amostra pode conter várias imagens. Uma contagem pode armazenar:

- método;
- versão do algoritmo;
- escala;
- magnificação;
- tamanho calibrado de pixel;
- foco e qualidade;
- componentes encontrados;
- quantidade;
- metadados das detecções;
- fotografia correspondente.

## API Python

A API recebe a chave no cabeçalho `X-API-Key`.

Ações implementadas:

- `patient_upsert`
- `patient_search`
- `sample_create`
- `count_create`

A aplicação `teste04.py` usa essas ações automaticamente.

Exemplo:

```bash
python teste04.py \
  --api-url https://servidor/hemacias/web \
  --api-key SUA_CHAVE \
  --patient-name "Paciente de teste" \
  --patient-external-id PAC-0001 \
  --sample-code AMOSTRA-0001 \
  --scale-label 40x \
  --magnification 40
```

Durante a captura, pressione `S` para enviar o frame, a contagem e os metadados.

## Segurança

As imagens armazenadas em `uploads/` são bloqueadas para acesso direto no Apache e são entregues por `image.php` somente depois de autenticação.

Para produção:

- use HTTPS;
- mantenha backups criptografados/protegidos;
- use uma conta MySQL exclusiva com privilégios mínimos;
- troque periodicamente a API key;
- não reutilize a `install_key`;
- mantenha PHP/MySQL atualizados;
- defina política institucional de acesso e retenção dos dados.


## Anotação e revisão de imagens

O gerenciador possui uma tela de anotação por imagem:

```text
annotation.php?image_id=ID
```

Ela permite:

- desenhar polígonos diretamente sobre a imagem;
- classificar como hemácia, leucócito, plaqueta, artefato ou outro;
- importar as detecções automáticas existentes para revisão;
- excluir falsos positivos;
- desenhar objetos ausentes (falsos negativos);
- salvar a revisão sem alterar o resultado automático original;
- exportar as anotações aprovadas em LabelMe JSON;
- exportar em YOLO Segmentation TXT.

Para um banco já existente, execute:

```sql
web/migrations/002_annotations.sql
```

Instalações novas já recebem essas tabelas por `schema.sql`.

As tabelas `image_annotations` e `annotation_revisions` registram os polígonos revisados, usuário e histórico da revisão.
