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

O detector atual identifica automaticamente apenas hemácias. O banco e a API já aceitam leucócitos, plaquetas e outros componentes para contagens manuais ou futuros detectores.

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

## Próximos passos recomendados

- calibração por câmera/microscópio;
- implementação de watershed para células sobrepostas;
- ferramenta de avaliação contra contagem manual;
- conversão das anotações LabelMe para formato de treinamento;
- métricas MAE, erro percentual, precisão, recall e F1;
- interface gráfica e exportação de resultados.

## Licença

Defina uma licença antes de distribuir ou reutilizar o projeto externamente.
