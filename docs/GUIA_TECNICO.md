# Guia técnico — Hemácias

Este guia reúne o que interessa a quem desenvolve, treina modelos ou avalia a contagem. Para operar o sistema no dia a dia, veja o [Manual do usuário](MANUAL_USUARIO.md).

## Sumário

- [Contador em tempo real](#contador-em-tempo-real)
- [Métodos de detecção](#métodos-de-detecção)
- [Controle de qualidade da imagem](#controle-de-qualidade-da-imagem)
- [Integração com o gerenciador web](#integração-com-o-gerenciador-web)
- [Segmentação supervisionada com YOLO](#segmentação-supervisionada-com-yolo)
- [Contagem multiclasse](#contagem-multiclasse)
- [Pipeline Blood Seg](#pipeline-blood-seg)
- [Prontidão científica do dataset](#prontidão-científica-do-dataset)
- [Avaliação contra contagem manual](#avaliação-contra-contagem-manual)
- [Validação contra ground truth revisado](#validação-contra-ground-truth-revisado)
- [Aplicativo Lazarus](#aplicativo-lazarus)
- [Geração do instalador](#geração-do-instalador)
- [Histórico de correções do núcleo](#histórico-de-correções-do-núcleo)
- [Próximos passos](#próximos-passos)

## Contador em tempo real

O programa principal em Python é o `teste04.py`. Ele abre a câmera, detecta as células em cada quadro, mostra a contagem estabilizada e, se a API estiver configurada, grava o resultado no gerenciador web.

```bash
python teste04.py --list-videos
python teste04.py --index 1 --method watershed --min-radius 15 --max-radius 35
```

### Opções

| Opção | Padrão | Significado |
|---|---|---|
| `-lv`, `--list-videos` | — | Lista os dispositivos de vídeo e encerra |
| `-ind`, `--index` | `0` | Índice da câmera |
| `--width`, `--height` | — | Resolução pedida à câmera |
| `--method` | `watershed` | Método de detecção: `hough`, `watershed` ou `yolo` |
| `--min-radius` | `15` | Raio mínimo esperado da hemácia, em pixels |
| `--max-radius` | `35` | Raio máximo esperado da hemácia, em pixels |
| `--min-distance` | `10` | Distância mínima entre centros (Hough) |
| `--param1` | `40.0` | Limiar superior do Canny usado pelo Hough |
| `--param2` | `20.0` | Limiar do acumulador do Hough |
| `--min-circularity` | `0.30` | Circularidade mínima (Watershed) |
| `--distance-ratio` | `0.38` | Separação de centros no Watershed, de 0 a 1 |
| `--focus` | `35.0` | Foco mínimo aceito antes de contar |
| `--history` | `15` | Quadros usados para estabilizar a contagem |
| `--model` | — | Arquivo `.pt` do YOLO; se omitido, usa o modelo do protocolo |
| `--confidence` | `0.25` | Confiança mínima do YOLO |
| `--iou` | `0.70` | IoU usado pelo YOLO |
| `--api-url` | — | Endereço da pasta `web`, por exemplo `https://servidor/hemacias/web` |
| `--api-key` | — | Chave definida em `web/config.php` |
| `--patient-name` | — | Nome do paciente |
| `--patient-external-id` | — | Identificador externo do paciente |
| `--birth-date` | — | Nascimento, no formato `AAAA-MM-DD` |
| `--sex` | — | Sexo ou descrição |
| `--document` | — | Documento ou identificador opcional |
| `--sample-code` | — | Código da amostra |
| `--protocol-code` | `sangue_padrao` | Protocolo de contagem cadastrado no servidor |
| `--scale-label` | do protocolo | Escala ou objetiva, por exemplo `40x` |
| `--magnification` | do protocolo | Magnificação |
| `--pixel-size-um` | — | Tamanho calibrado do pixel, em µm |
| `--allow-low-quality-save` | — | Permite gravar um campo rejeitado pelo controle de qualidade |

`--api-url` e `--api-key` precisam ser informados juntos. Se o paciente ou a amostra não forem passados na linha de comando, o programa pergunta no terminal.

### Teclas durante a execução

| Tecla | Ação |
|---|---|
| `Q` | Encerra |
| `C` | Limpa o histórico usado para estabilizar a contagem |
| `S` | Envia o quadro, a contagem e as detecções ao gerenciador web |

O `teste03.py` é o experimento anterior, mantido só para comparação.

## Métodos de detecção

| Método | Arquivo | Classes | Como funciona |
|---|---|---|---|
| `hough` | `hemacias/counter.py` | Hemácia | Transformada de Hough para círculos, depois de suavização. Serve de linha de base |
| `watershed` | `hemacias/watershed.py` | Hemácia | Limiarização, morfologia, transformada de distância e watershed, o que separa melhor células encostadas. É o padrão |
| `yolo` | `hemacias/yolo_counter.py` | Todas as do modelo | Rede treinada; devolve classe, confiança, caixa e, nos modelos de segmentação, o polígono da célula |

Os três métodos mantêm uma janela com as últimas detecções e exibem a **mediana**, para que um quadro com falso positivo não contamine a leitura. Hough e Watershed continuam experimentais e precisam ser ajustados com imagens reais de cada microscópio.

## Controle de qualidade da imagem

O módulo `hemacias/quality.py` classifica cada campo antes de aceitar a contagem. O Hemácias Analyzer aplica a mesma regra.

| Verificação | Limite | Efeito |
|---|---|---|
| Foco (variância do Laplaciano) | abaixo de 35 | Rejeição direta |
| Brilho médio | abaixo de 35 ou acima de 225 | Penalidade de 30 pontos |
| Pixels escuros (até 8 de 255) | mais de 12% da imagem | Penalidade de até 25 pontos |
| Pixels claros (247 ou mais) | mais de 12% da imagem | Penalidade de até 25 pontos |
| Desigualdade de iluminação entre nove regiões | coeficiente acima de 0,28 | Penalidade de até 30 pontos |

A nota parte de 100 e perde as penalidades. O estado final é:

| Estado | Condição |
|---|---|
| `REJEITADA` | Foco abaixo do mínimo, ou nota menor que 45 |
| `REVISAR` | Nota menor que 75, ou qualquer observação registrada |
| `ACEITA` | Os demais casos |

Campos rejeitados ficam fora da consolidação da amostra. No `teste04.py`, a tecla `S` não envia um campo rejeitado, a não ser que a execução tenha `--allow-low-quality-save` ou que o protocolo dispense o controle de qualidade.

## Integração com o gerenciador web

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

O cliente (`hemacias/api_client.py`) cadastra ou localiza o paciente, cria a amostra, lê a configuração do protocolo e, a cada tecla `S`, envia um campo microscópico com imagem, contagem, detecções e resultado do controle de qualidade. A chave vai no cabeçalho `X-API-Key`. A lista de ações da API e as regras de segurança estão em [`web/README.md`](../web/README.md).

Quando o protocolo tem um modelo padrão cadastrado, o cliente confere o SHA-256 do arquivo antes de abrir o YOLO e só aceita modelos com estado `VALIDACAO` ou `APROVADO`.

## Segmentação supervisionada com YOLO

### 1. Converter as anotações LabelMe

```bash
python tools/labelme_to_yolo_seg.py
```

O conversor cria:

```text
datasets/hemacias_seg/
├── dataset.yaml
├── images/
│   ├── train/
│   ├── val/
│   └── test/
└── labels/
    ├── train/
    ├── val/
    └── test/
```

Ele dá prioridade à imagem que tem o mesmo nome do JSON, porque há anotações antigas em que o campo `imagePath` não corresponde ao arquivo real. Por padrão o conversor é estrito: se `imagePath` não bate com o nome do JSON, a anotação é ignorada e uma mensagem de revisão aparece. Depois de conferir à mão, o comportamento pode ser liberado com `--allow-imagepath-mismatch`.

Para refazer a conversão sem resíduos da anterior:

```bash
python tools/labelme_to_yolo_seg.py --clean
```

A separação entre treino, validação e teste deve ser feita por campo ou imagem de origem, para evitar vazamento de dados.

### 2. Instalar as dependências de IA

```bash
pip install -r requirements-ml.txt
```

### 3. Treinar

```bash
python tools/train_yolo_seg.py \
  --data datasets/hemacias_seg/dataset.yaml \
  --epochs 100 \
  --imgsz 640
```

O treinamento parte de um modelo de segmentação pré-treinado, como recomenda a documentação do Ultralytics. O padrão é `yolo26n-seg.pt`; outro modelo-base pode ser indicado com `--model`. O script não inicia se não houver rótulos em `train` e em `val`. Com `--api-url`, `--api-key` e `--registry-version`, o modelo treinado é registrado no gerenciador web.

### 4. Usar o modelo treinado

```bash
python teste04.py \
  --method yolo \
  --model runs/hemacias/seg/weights/best.pt
```

Com o gerenciador web:

```bash
python teste04.py \
  --method yolo \
  --model runs/hemacias/seg/weights/best.pt \
  --api-url https://servidor/hemacias/web \
  --api-key SUA_CHAVE \
  --patient-name "Paciente de teste" \
  --sample-code AMOSTRA-001
```

Cada previsão registra classe, confiança, caixa delimitadora e, quando houver, o polígono da máscara.

> O modelo treinado deve ser validado em uma base separada antes de qualquer uso laboratorial.

## Contagem multiclasse

O método `yolo` não filtra só hemácias: todas as classes previstas pelo modelo são preservadas e agrupadas.

```text
hemacia: 132
leucocito: 4
plaqueta: 27
artefato: 3
```

Cada classe vai ao servidor como um componente de contagem separado, com quantidade, confiança média, detecções individuais, caixa delimitadora, polígono da máscara e a contagem estabilizada daquela classe. O nome, a unidade e o limiar de confiança de cada componente vêm do protocolo da amostra.

Hough e Watershed continuam contando apenas hemácias, para comparação com o processamento clássico.

## Pipeline Blood Seg

O treinamento multiclasse pode ser repetido de forma controlada com:

```bash
python tools/blood_seg_pipeline.py \
  --version v1 \
  --dataset-ref dataset-2026-09-19-v1 \
  --data datasets/hemacias_seg/dataset.yaml \
  --api-url https://servidor/hemacias/web \
  --api-key SUA_CHAVE \
  --epochs 100 \
  --imgsz 1024 \
  --batch 8 \
  --device 0 \
  --reference-csv referencia_multiclasse.csv
```

O pipeline:

1. valida a existência de rótulos de treino e validação;
2. treina o YOLO de segmentação;
3. localiza o `best.pt`;
4. calcula o SHA-256;
5. registra `Blood Seg <versão>` com estado `VALIDACAO`;
6. publica as métricas globais de segmentação devolvidas pelo Ultralytics;
7. quando há `--reference-csv`, compara a contagem manual com a automática;
8. publica MAE, viés e MAPE, globais e por componente;
9. mantém o modelo em `VALIDACAO` até a aprovação explícita no gerenciador.

O script nunca promove um modelo para `APROVADO` por conta própria.

## Prontidão científica do dataset

Antes de treinar, execute:

```bash
python tools/check_yolo_dataset.py datasets/hemacias_seg/dataset.yaml --strict
```

A verificação cobre:

- presença de TRAIN, VAL e TEST;
- rótulos sem imagem;
- imagens sem rótulo, sinalizadas para confirmar se são negativos intencionais;
- formato das segmentações YOLO;
- cobertura das classes em validação e teste;
- presença de `manifest.json`;
- proveniência da divisão;
- agrupamento por paciente, no modo estrito.

O `tools/blood_seg_pipeline.py` roda essa verificação sozinho antes de treinar. Para datasets antigos sem proveniência existe `--allow-untracked-dataset`, destinado só a experimentação.

Para auditar as anotações LabelMe do repositório:

```bash
python tools/audit_dataset.py
```

A ferramenta gera `dataset_audit.json` e atualiza [`DATASET_AUDIT.md`](DATASET_AUDIT.md), conferindo pares imagem/JSON, `imagePath`, classes, tipos de forma, polígonos inválidos, pontos fora da imagem e cobertura de anotação.

## Avaliação contra contagem manual

Prepare um CSV:

```csv
image,manual_count
campo01.jpg,47
campo02.jpg,51
```

Execute:

```bash
python tools/evaluate_counts.py referencia.csv --method watershed
```

A ferramenta calcula MAE, erro percentual médio (quando aplicável) e viés médio, e grava o detalhe em CSV (`evaluation_results.csv`, por padrão). Há um modelo de arquivo em `tools/reference_example.csv`.

Para avaliação multiclasse, use a coluna `class`:

```csv
image,class,manual_count
campo01.jpg,hemacia,132
campo01.jpg,leucocito,4
campo01.jpg,plaqueta,27
campo02.jpg,hemacia,141
```

```bash
python tools/evaluate_counts.py referencia_multiclasse.csv \
  --method yolo \
  --model runs/hemacias/seg/weights/best.pt
```

O resultado traz MAE, viés e MAPE, no geral e por classe. Com `--api-url`, `--api-key` e `--model-id`, as métricas são publicadas no cadastro do modelo.

## Validação contra ground truth revisado

Depois que as imagens analisadas forem revisadas à mão e marcadas como `REVISADA` ou `APROVADA`, o modelo pode ser validado diretamente contra esse gabarito:

```bash
python tools/evaluate_reviewed_annotations.py \
  --api-url https://servidor/hemacias/web \
  --api-key SUA_CHAVE \
  --model-id 1 \
  --iou 0.50 \
  --json-output runs/validation/blood-seg-v1.json
```

É possível definir um IoU diferente por classe:

```bash
python tools/evaluate_reviewed_annotations.py \
  --api-url https://servidor/hemacias/web \
  --api-key SUA_CHAVE \
  --model-id 1 \
  --iou 0.50 \
  --class-iou hemacia=0.50 \
  --class-iou leucocito=0.55 \
  --class-iou plaqueta=0.40
```

O avaliador:

1. busca só as imagens ligadas ao modelo que tenham gabarito manual aprovado;
2. separa os objetos por classe;
3. calcula o IoU poligonal real;
4. casa previsões e gabarito do maior IoU para o menor, dentro da mesma classe;
5. calcula TP, FP, FN, precisão, recall e F1;
6. calcula MAE, viés e MAPE de contagem por imagem e classe;
7. publica as métricas gerais e por classe em `ai_model_metrics`;
8. registra a rodada completa em `ai_model_validation_runs`.

Use `--no-publish` para rodar só a análise local, sem alterar o registro do modelo.

Em banco já existente, aplique também `web/migrations/009_model_validation_runs.sql`.

As métricas publicadas por essa ferramenta representam **validação contra gabarito humano revisado**, e não as métricas internas do conjunto de validação usadas durante o treinamento.

## Aplicativo Lazarus

O código do Hemácias Analyzer está em `lazarus/hemacias_analyzer/`. Ele usa a biblioteca [`marcelomaurin/CHATGPT`](https://github.com/marcelomaurin/CHATGPT) por meio de `TPythonConnector` (ponte com o Python), `TYOLO` (inferência), `TAICaptureSource` (câmera), `TBrightnessContrastFilter` e `TAIFrameProcessor` (ajustes de imagem) e `TCHATGPT` (parecer textual opcional). O `TCHATGPT` recebe apenas os números do relatório para redigir um resumo; ele não faz a contagem.

Requisitos, compilação com `lazbuild` e a descrição de cada unidade Pascal estão em [`lazarus/hemacias_analyzer/README.md`](../lazarus/hemacias_analyzer/README.md).

| Unidade | Papel |
|---|---|
| `main.pas` | Tela principal e fluxo de análise |
| `measurement_types.pas` | Tipos de perfil óptico, medição por célula, estatísticas e dados hematológicos |
| `morphometry.pas` | Área, perímetro, diâmetro equivalente, circularidade, eixos, percentis e índices |
| `calibration.pas` | Escala teórica e calibração por régua micrométrica |
| `camera_service.pas` | Descoberta de câmeras e captura de quadros |
| `hemacias_api.pas` | Cliente da API do gerenciador web |

## Geração do instalador

Os instaladores em `bin/` são gerados com o Inno Setup a partir de `installer_v1.0.iss` e `installer_v1.2.iss`. O roteiro da versão 1.2 empacota:

- o executável `hemacias_analyzer.exe`;
- os modelos `blood-seg-v1.pt`, `best.pt`, `blood-cell-bccd-yolov8s.pt`, `blood-cell-bccd-yolov8n.pt`, `blood-seg-v1.onnx`, `yolo11n-seg.pt` e `yolo11n.pt`;
- `python/camera_capture.py`, `instalar_dependencias.bat` e os arquivos de requisitos;
- o README principal e o do aplicativo Lazarus.

Os caminhos de origem do roteiro apontam para `D:\projetos\maurinsoft\hemacias`; ajuste-os se o repositório estiver em outra pasta. Ao final da instalação, o instalador avisa se o Python não foi encontrado no PATH.

## Histórico de correções do núcleo

A implementação original mantinha como resultado o maior número de círculos encontrado desde o início da execução. Um único quadro com falso positivo podia, assim, contaminar o resultado para sempre. A versão atual mantém uma janela temporal e usa a mediana das últimas detecções.

Também foram corrigidos:

- abertura e liberação da câmera;
- referência inválida a `cap` em `teste03.py`;
- captura duplicada em `teste03.py`;
- enumeração de câmeras;
- caminhos absolutos de Windows no conversor;
- funções duplicadas no conversor;
- parâmetros fixos, agora expostos pela linha de comando;
- avaliação simples de foco antes da contagem;
- organização do código em módulos reutilizáveis.

## Próximos passos

- calibração por câmera e microscópio;
- ajuste e validação do watershed em campos reais;
- anotação dos conjuntos de teste e das imagens coloridas;
- métricas MAE, erro percentual, precisão, recall e F1 em base independente;
- validação formal, conforme o [Plano de melhorias](PLANO_MELHORIAS.md).
