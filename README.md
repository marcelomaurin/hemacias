# Hemácias

Projeto experimental para **detecção e contagem de hemácias em imagens de microscopia usando visão computacional**.

O artigo que originou o trabalho está disponível em:
https://maurinsoft.com.br/projeto-contagem-de-hemacias/

## Situação atual

O projeto utiliza OpenCV para captura de vídeo, pré-processamento da imagem e detecção circular. A versão atual foi refatorada para separar câmera, processamento e interface, corrigir o gerenciamento da câmera e estabilizar a contagem entre vários frames.

> **Importante:** este projeto é experimental e educacional. A contagem automática deve ser validada contra um método de referência antes de qualquer uso laboratorial ou diagnóstico.

## Estrutura

- `hemacias/camera.py`: descoberta e abertura de câmeras.
- `hemacias/counter.py`: pré-processamento, avaliação de foco, detecção e estabilização da contagem.
- `teste04.py`: aplicação principal em tempo real.
- `teste03.py`: experimento legado mantido para comparação.
- `python/tools/converte/converte.py`: conversor portátil de imagens do dataset.
- `fotos/`: imagens e anotações experimentais/LabelMe.
- `tests/`: testes básicos do núcleo.
- `web/`: gerenciador PHP/MySQL, API, pacientes, amostras, contagens e imagens.
- `docs/PLANO_MELHORIAS.md`: plano de evolução técnica e validação.

## Instalação

Requer Python 3.10 ou superior.

```bash
python -m venv .venv
```

Windows:

```bat
.venv\Scripts\activate
pip install -r requirements.txt
```

Linux:

```bash
source .venv/bin/activate
pip install -r requirements.txt
```

## Uso

Listar câmeras:

```bash
python teste04.py --list-videos
```

Executar com a câmera padrão:

```bash
python teste04.py
```

Selecionar outra câmera:

```bash
python teste04.py --index 1
```

Ajustar a faixa de tamanho esperada:

```bash
python teste04.py --min-radius 15 --max-radius 35
```

Usar o novo método de segmentação:

```bash
python teste04.py --method watershed --min-radius 15 --max-radius 35
```

Comparar com o método anterior:

```bash
python teste04.py --method hough
```

O `watershed` é agora o método padrão porque permite separar melhor objetos celulares adjacentes. Ele continua sendo experimental e precisa ser calibrado com imagens reais.

Durante a execução:

- `Q`: encerra.
- `C`: limpa o histórico usado para estabilizar a contagem.
- `S`: quando a API está configurada, registra o frame, a contagem e as detecções no gerenciador web.

## Gerenciador web PHP/MySQL

O diretório `web/` contém o sistema de gestão com:

- autenticação e perfis;
- cadastro de pacientes;
- várias amostras por paciente;
- várias contagens por amostra;
- vários componentes sanguíneos por contagem;
- várias imagens por amostra;
- escala, magnificação, foco e método;
- API autenticada por chave para integração com Python;
- auditoria administrativa.

Instalação resumida:

1. importe `web/schema.sql`;
2. copie `web/config.example.php` para `web/config.php`;
3. configure MySQL, chaves e URL;
4. acesse `web/install.php` para criar o primeiro administrador.

Consulte `web/README.md` para os detalhes.

Exemplo de integração Python:

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

Hough e Watershed continuam especializados em hemácias. O método YOLO agora é multiclasse e envia uma contagem separada para cada classe prevista pelo modelo, como hemácia, leucócito, plaqueta e artefato.

## O que foi corrigido

A implementação anterior mantinha como resultado o maior número de círculos encontrado desde o início da execução. Um frame com falso positivo podia, portanto, contaminar permanentemente o resultado.

A versão atual mantém uma janela temporal e usa a **mediana das últimas detecções**, produzindo uma leitura mais estável.

Também foram corrigidos:

- abertura e liberação da câmera;
- referência inválida a `cap` em `teste03.py`;
- captura duplicada em `teste03.py`;
- enumeração de câmeras;
- caminhos absolutos de Windows no conversor;
- funções duplicadas no conversor;
- parâmetros fixos expostos agora pela linha de comando;
- avaliação simples de foco antes da contagem;
- organização do código em módulos reutilizáveis.

## Dataset

O repositório já possui imagens de treino/teste e anotações LabelMe com a classe `hemacia`. Esse material pode ser usado em uma próxima etapa para comparar:

1. Hough Circles;
2. segmentação clássica com watershed;
3. segmentação supervisionada (por exemplo, YOLO Segmentation).

A separação de treino, validação e teste deve ser feita por campo/imagem de origem para evitar vazamento de dados.

## Avaliação contra contagem manual

Foi adicionada a ferramenta `tools/evaluate_counts.py`. Prepare um CSV:

```csv
image,manual_count
campo01.jpg,47
campo02.jpg,51
```

Execute:

```bash
python tools/evaluate_counts.py referencia.csv --method watershed
```

Ela calcula MAE, erro percentual médio (quando aplicável), viés médio e grava resultados detalhados em CSV.

## Próximos passos recomendados

- calibração por câmera/microscópio;
- ajuste/validação do watershed em campos reais;
- conversão das anotações LabelMe para dataset de segmentação;
- conversão das anotações LabelMe para formato de treinamento;
- métricas MAE, erro percentual, precisão, recall e F1;
- interface gráfica e exportação de resultados.

## Licença

Defina uma licença antes de distribuir ou reutilizar o projeto externamente.


## Segmentação supervisionada (YOLO)

O projeto agora possui um terceiro método de análise baseado em segmentação supervisionada.

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

O conversor prioriza a imagem com o mesmo nome do JSON porque existem anotações antigas cujo campo `imagePath` pode não corresponder ao arquivo real.

### 2. Instalar dependências de IA

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

A documentação atual do Ultralytics recomenda usar um modelo de segmentação pré-treinado para iniciar o treino de um dataset customizado. O script usa `yolo26n-seg.pt` como padrão.

### 4. Usar o modelo treinado

Depois do treinamento, use o `best.pt`:

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

Cada previsão registra classe, confiança, caixa delimitadora e polígono da máscara quando disponível.

> O modelo treinado deve ser validado em uma base separada antes de qualquer uso laboratorial.


## Contagem multiclasse de componentes sanguíneos

O método `yolo` não filtra mais somente hemácias. Todas as classes previstas pelo modelo treinado são preservadas e agrupadas.

Exemplo de resultado:

```text
hemacia: 132
leucocito: 4
plaqueta: 27
artefato: 3
```

Cada classe é enviada como um `count_component` separado, com:

- quantidade;
- confiança média;
- detecções individuais;
- bounding box;
- polígono da máscara;
- contagem estabilizada daquela classe.

Hough e Watershed permanecem hemácia-only para comparação com o pipeline clássico.

### Avaliação multiclasse

O CSV de referência pode usar a coluna `class`:

```csv
image,class,manual_count
campo01.jpg,hemacia,132
campo01.jpg,leucocito,4
campo01.jpg,plaqueta,27
campo02.jpg,hemacia,141
```

Execute:

```bash
python tools/evaluate_counts.py referencia_multiclasse.csv \
  --method yolo \
  --model runs/hemacias/seg/weights/best.pt
```

A ferramenta mostra MAE, viés e MAPE geral e por classe.


## Pipeline Blood Seg

O treinamento multiclasse pode ser executado de forma reproduzível com:

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

1. valida a existência de labels de treino e validação;
2. treina o YOLO Segmentation;
3. localiza `best.pt`;
4. calcula SHA-256;
5. registra `Blood Seg <versão>` como `VALIDACAO`;
6. publica métricas globais de segmentação retornadas pelo Ultralytics;
7. quando `--reference-csv` é fornecido, executa a comparação de contagem manual x automática;
8. publica MAE, viés e MAPE global e por componente;
9. mantém o modelo em `VALIDACAO` até aprovação explícita no gerenciador.

O script não promove automaticamente um modelo para `APROVADO`.


## Prontidão científica do dataset

Antes do treinamento, execute:

```bash
python tools/check_yolo_dataset.py datasets/hemacias_seg/dataset.yaml --strict
```

A verificação cobre:

- presença de TRAIN, VAL e TEST;
- labels sem imagem;
- imagens sem label, sinalizadas para confirmar negativos intencionais;
- formato das segmentações YOLO;
- cobertura das classes em validação e teste;
- presença de `manifest.json`;
- proveniência do split;
- agrupamento por paciente no modo estrito.

O `tools/blood_seg_pipeline.py` executa essa verificação automaticamente antes de iniciar o treinamento. Para datasets legados sem proveniência, existe `--allow-untracked-dataset`, destinado somente a experimentação.

Para reconstruir um dataset LabelMe local sem resíduos de uma conversão anterior:

```bash
python tools/labelme_to_yolo_seg.py --clean
```


## Aplicação Lazarus para análise de lâminas

Foi adicionada uma aplicação desktop em:

```text
lazarus/hemacias_analyzer/
```

Ela usa a biblioteca `marcelomaurin/CHATGPT` por meio de:

- `TPythonConnector`;
- `TYOLO`;
- `TCHATGPT`.

A aplicação carrega uma imagem individual de lâmina, executa o modelo YOLO configurado, conta objetos por classe, desenha as detecções, calcula confiança média e emite resultados em JSON, CSV ou TXT. O `TCHATGPT` é opcional e recebe apenas os resultados numéricos para redigir um resumo técnico; ele não realiza a contagem.


## Validação automática contra ground truth revisado

Depois que imagens analisadas forem revisadas manualmente e marcadas como `REVISADA` ou `APROVADA`, o modelo pode ser validado diretamente contra esse ground truth:

```bash
python tools/evaluate_reviewed_annotations.py \
  --api-url https://servidor/hemacias/web \
  --api-key SUA_CHAVE \
  --model-id 1 \
  --iou 0.50 \
  --json-output runs/validation/blood-seg-v1.json
```

É possível definir IoU diferente por classe:

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

1. busca somente imagens ligadas ao modelo e com ground truth manual aprovado;
2. separa objetos por classe;
3. calcula IoU poligonal real;
4. faz matching guloso do maior IoU para o menor dentro da mesma classe;
5. calcula TP, FP, FN, precision, recall e F1;
6. calcula MAE, viés e MAPE de contagem por imagem/classe;
7. publica métricas gerais e por classe em `ai_model_metrics`;
8. registra a rodada completa em `ai_model_validation_runs`.

Use `--no-publish` para executar somente a análise local sem alterar o registro do modelo.

Para banco existente, execute também:

```sql
web/migrations/009_model_validation_runs.sql
```

As métricas publicadas por essa ferramenta representam **validação contra ground truth humano revisado**, e não as métricas internas do conjunto de validação usadas durante o treinamento.


---

## 7. Detecção automática da resolução da câmera

O sistema implementa detecção automática e seleção metrológica de resolução para câmeras de microscopia:

1. **Consulta direta ao hardware/driver**:
   O sistema tenta consultar diretamente os modos suportados pelo dispositivo de captura (via DirectShow / OpenCV backend). Quando a consulta ao hardware é bem-sucedida, a origem dos modos é rotulada como `DEVICE_REPORTED`. Se o driver não responder à enumeração de capacidades, o sistema utiliza presets genéricos padronizados (`GENERIC_PRESET`, de 640×480 até 3840×2160).

2. **Seleção Automática / Melhor disponível**:
   Em modo automático, é selecionada a maior resolução disponível baseada na quantidade total de pixels ($	ext{Largura} 	imes 	ext{Altura}$). Em caso de empate, prevalece o maior FPS. Para microscopia óptica, a resolução espacial tem prioridade sobre a taxa de quadros por segundo. O usuário também pode selecionar manualmente qualquer modo detectado através do seletor na interface.

3. **Conferência da resolução efetiva pós-captura**:
   A resolução efetivamente retornada pelo driver é conferida após a captura física do frame a partir das dimensões reais do bitmap gravado. O sistema **não assume** que a resolução entregue é idêntica à solicitada: se a câmera retornar uma resolução diferente (ex: solicitada 1920×1080 mas entregue 1600×1200 ou 1280×720), o evento é registrado e a imagem é preservada sem distorções nem resizes artificiais.

4. **Resolução efetiva no perfil óptico**:
   A resolução efetiva recebida (`AcquisitionWidthPX`, `AcquisitionHeightPX`) é a única utilizada no perfil óptico e na determinação de fatores de redimensionamento e escala. A resolução solicitada é armazenada separadamente (`RequestedWidthPX`, `RequestedHeightPX`) para auditoria metrológica.

5. **Independência entre Megapixels e Escala Física ($\mu	ext{m/px}$)**:
   > **AVISO METROLÓGICO CRÍTICO**: A resolução em Megapixels **NÃO** determina a escala óptica em $\mu	ext{m/pixel}$.
   > O tamanho físico de cada pixel do sensor (`SensorPixelSizeUM`) é uma propriedade intrínseca da matriz semicondutora do sensor CMOS/CCD e das dimensões físicas da pastilha de silício (ex: $3,45\,\mu	ext{m}$, $2,4\,\mu	ext{m}$, $1,45\,\mu	ext{m}$). Câmeras de mesma contagem de Megapixels podem ter sensores físicos de tamanhos completamente diferentes (ex: 1/2.8", 1/1.8", 1"). Portanto, `SensorPixelSizeUM` continua sendo uma informação independente obtida da ficha técnica do fabricante ou calibrada fisicamente via micrômetro de lâmina, e **nunca** deve ser deduzida apenas pela resolução em pixels.
