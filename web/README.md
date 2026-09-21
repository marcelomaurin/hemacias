# Gerenciador Web

Requisitos:

- PHP 8.1+
- MySQL 5.7+/8.0+
- extensões PDO MySQL e FileInfo
- servidor HTTPS em produção

## Instalação e Auto-Instalador

1. Copie `config.example.php` para `config.php`.
2. Configure as credenciais do banco MySQL, `api_key`, `install_key` e diretório de upload. (Em hospedagens como Hostinger/hPanel, use `host=localhost` e inclua o prefixo da sua conta no `dbname` e `user`).
3. Garanta permissão de escrita para `web/uploads/`.
4. Acesse `install.php` no navegador.
5. O painel de Auto-Instalação detectará o banco e executará a criação das tabelas e migrações automaticamente com 1 clique (sem necessidade de importar arquivos no phpMyAdmin).
6. Cadastre o primeiro administrador na mesma tela usando a `install_key` definida no seu `config.php`.
7. Acesse `index.php`.

Nunca versione `config.php`: ele contém credenciais e chaves.

## Arquitetura MVC & WebService (WS)

A aplicação agora segue o padrão MVC e comunicação desacoplada via WebService em PHP:
- **Models** (`web/lib/Models/`): `UserModel`, `PatientModel`, `SampleModel`, `VersionModel`, `BaseModel`.
- **Controllers** (`web/lib/Controllers/`): `AuthWsController`, `InstallWsController`, `VersionWsController`, `PatientWsController`, `SampleWsController`.
- **WebService** (`web/ws.php`): Endpoint JSON unificado (`action=...`) com captura graciosa de exceções e respostas estruturadas sem páginas de erro 500 em branco.
- **Controle de Versão**:
  - `system_version` e `schema_migrations` gravados no MySQL.
  - Constante de versão em `App::VERSION` (v1.1.0) e schema alvo (`v10`).
  - Rodapé e telas exibem dinamicamente a versão da aplicação e o status de atualização do banco.

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
- `config`
- `model_register`
- `model_metric_upsert`
- `models_list`
- `sample_summary`
- `annotations_save`

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


## Gerenciador de dataset

Acesse:

```text
dataset.php
```

A tela permite:

- visualizar imagens pendentes, revisadas, aprovadas e rejeitadas;
- filtrar por paciente, amostra, estado e split;
- definir `TRAIN`, `VAL`, `TEST` ou `NAO_DEFINIDO`;
- incluir/excluir imagens do dataset;
- visualizar estatísticas por classe;
- aplicar split em lote;
- abrir a revisão da imagem;
- exportar em lote um ZIP YOLO Segmentation.

Para bancos existentes, execute:

```sql
web/migrations/003_dataset_manager.sql
```

O estado é atualizado automaticamente:

```text
detecção importada -> PENDENTE
revisão manual salva -> REVISADA
aprovação no gerenciador -> APROVADA
```

A exportação considera somente imagens:

```text
review_state = APROVADA
included = 1
split = TRAIN / VAL / TEST
```

O ZIP contém:

```text
dataset.yaml
manifest.json
images/train
images/val
images/test
labels/train
labels/val
labels/test
```

A exportação em ZIP requer a extensão PHP `ZipArchive`.


## Split automático sem vazamento

O gerenciador de dataset agora possui divisão automática de imagens aprovadas.

Modos disponíveis:

- `SAMPLE`: mantém todas as imagens da mesma amostra no mesmo split;
- `PATIENT`: mantém todas as imagens do mesmo paciente no mesmo split.

O modo por paciente é mais rigoroso quando várias amostras do mesmo paciente podem compartilhar características visuais.

Proporção padrão:

```text
TRAIN 70%
VAL   15%
TEST  15%
```

As proporções podem ser alteradas, desde que somem 1,0.

A divisão usa uma `seed` informada pelo usuário e é determinística para o mesmo conjunto de grupos. O algoritmo tenta aproximar a proporção desejada pelo número de imagens sem quebrar grupos.

Cada execução é registrada em `dataset_split_runs` com:

- modo de agrupamento;
- proporções;
- seed;
- quantidade de imagens elegíveis;
- número de grupos;
- resultado TRAIN/VAL/TEST;
- usuário;
- data/hora;
- atribuições realizadas.

Para bancos existentes, execute:

```sql
web/migrations/004_dataset_auto_split.sql
```


## Campos microscópicos e consolidação

Cada captura salva pela API passa a criar um **campo microscópico** ligado à amostra, à contagem e à imagem.

Acesse:

```text
sample_analysis.php?sample_id=ID
```

A página mostra:

- total de campos;
- campos válidos;
- campos rejeitados/excluídos;
- campos para revisão;
- média por componente;
- mediana;
- mínimo;
- máximo;
- desvio-padrão amostral;
- revisão manual do status de cada campo.

O controle automático de qualidade considera:

- foco;
- brilho médio;
- excesso de sombras;
- excesso de altas luzes;
- desigualdade de iluminação.

Estados:

```text
ACEITA
REVISAR
REJEITADA
```

Campos rejeitados ficam fora da consolidação por padrão.

No Python, um campo `REJEITADA` não é enviado quando o usuário pressiona `S`, salvo se a execução tiver:

```bash
--allow-low-quality-save
```

Para bancos existentes, execute:

```sql
web/migrations/005_microscopic_fields.sql
```


## Gestão central de componentes e protocolos

O sistema possui uma camada de configuração em:

```text
resources.php
```

Acesso restrito a ADMIN.

### Componentes de contagem

Cada componente possui:

- código;
- nome;
- categoria;
- cor;
- unidade padrão;
- ativo/inativo;
- habilitado para IA;
- habilitado para anotação;
- habilitado para consolidação;
- limiar mínimo de confiança;
- ID da classe YOLO;
- ordem de apresentação.

Os componentes padrão são hemácia, leucócito, plaqueta, artefato e outro, mas novas classes podem ser cadastradas sem alteração do código-fonte.

### Protocolos

Um protocolo define:

- componentes participantes;
- componentes obrigatórios;
- limiar de confiança por componente;
- se o componente entra na consolidação;
- número mínimo de campos;
- número mínimo de campos válidos;
- escala/magnificação padrão;
- exigência de controle de qualidade.

As amostras passam a possuir um protocolo associado.

### Integração

A ação de API `config` disponibiliza componentes e protocolos ao cliente Python. O `teste04.py` usa a configuração do protocolo para nome, unidade e limiar de confiança ao persistir detecções.

A anotação web e os exportadores LabelMe/YOLO também usam o cadastro central. O ID YOLO deixa de ser fixado em código.

Para bancos existentes, execute:

```sql
web/migrations/006_count_resources.sql
```


## Gestão de modelos de IA

Acesse:

```text
models.php
```

O cadastro registra versão, tipo, status, caminho do arquivo, SHA-256, dataset, `imgsz`, épocas, classes e data de treinamento.

Status disponíveis:

```text
TREINO
VALIDACAO
APROVADO
INATIVO
```

As métricas podem ser registradas globalmente ou por componente: precision, recall, F1, mAP50, mAP50-95, MAE, viés e MAPE.

Cada protocolo pode selecionar um modelo padrão. A API `config` retorna os metadados desse modelo ao cliente Python. Cada contagem armazena também uma fotografia da identidade do modelo utilizado:

- `model_id`;
- `model_version_snapshot`;
- `model_sha256_snapshot`.

Para bancos existentes, execute:

```sql
web/migrations/007_ai_models.sql
```


O caminho cadastrado do modelo deve ser acessível ao processo Python que executa a inferência. Para modelos cadastrados, o cliente valida o SHA-256 antes de abrir o YOLO. Quando `--model` é usado como override, o caminho e o SHA-256 efetivamente executados também são gravados como snapshot da contagem.


## Comparação de versões

Acesse:

```text
compare_models.php
```

Selecione dois ou mais modelos para visualizar lado a lado identificação, dataset, parâmetros e métricas globais/por componente. A tela não promove automaticamente um modelo; a alteração para `APROVADO` permanece uma ação administrativa explícita.


## Controles de qualidade do dataset

A revisão humana salva transforma os objetos mantidos em anotações `APROVADA`. A imagem permanece `REVISADA` até a aprovação final no gerenciador de dataset.

A importação automática não sobrescreve uma revisão humana sem uma confirmação explícita de reinicialização.

A divisão automática usa **PATIENT** como modo recomendado para validação. A exportação YOLO executa preflight e é bloqueada se detectar, entre outros problemas:

- paciente em mais de um split;
- amostra em mais de um split;
- TRAIN/VAL/TEST vazio;
- anotações pendentes em imagem aprovada;
- dimensões inválidas;
- classe sem ID YOLO;
- ID YOLO duplicado.

O `manifest.json` exportado registra a proveniência do split e a política de vazamento utilizada.


## Cliente desktop Lazarus

O projeto:

```text
lazarus/hemacias_analyzer/
```

pode enviar contagens diretamente para a mesma API. A ação `count_create` aceita tanto o multipart usado pelo cliente Python quanto JSON usado pelo Lazarus. No JSON, a imagem pode ser enviada com:

```json
{
  "image_name": "lamina.png",
  "image_base64": "..."
}
```

Contagens desse cliente são gravadas com:

```text
source = LAZARUS
```

Para banco existente, execute:

```sql
web/migrations/008_lazarus_source.sql
```

Se a análise informar `model_id` e o modelo cadastrado possuir SHA-256, a API rejeita um SHA diferente do registro.


### sample_summary

Retorna a visão consolidada de uma amostra para clientes desktop e integrações: campos microscópicos, situação de qualidade, contagens consolidadas e estatísticas por componente. Uma amostra é marcada como pronta somente quando atende simultaneamente o número total de campos e o número mínimo de campos válidos definidos pelo protocolo.


### annotations_save

Endpoint autenticado por `X-API-Key` destinado a clientes desktop. Recebe `image_id` e a lista completa de anotações revisadas, valida classe e geometria e grava o resultado como ground truth manual aprovado. A imagem é marcada como `REVISADA` no gerenciador de dataset. A operação preserva a contagem automática original e registra a correção humana separadamente.


## Validação de modelos com ground truth

A API possui os endpoints:

```text
validation_data
validation_run_register
```

`validation_data` retorna apenas imagens vinculadas ao `model_id` que possuam revisão humana aprovada no dataset, preservando separadamente as predições automáticas e o ground truth.

`validation_run_register` grava o histórico da execução em `ai_model_validation_runs`.

Para bancos existentes:

```sql
web/migrations/009_model_validation_runs.sql
```

As métricas publicadas por `tools/evaluate_reviewed_annotations.py` recebem observação indicando que são provenientes de validação contra ground truth revisado.
