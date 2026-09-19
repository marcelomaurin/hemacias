# Hemácias Analyzer — Lazarus

Aplicação desktop para análise experimental de **uma lâmina/imagem microscópica por vez**, usando a biblioteca Lazarus AI Suite do repositório `marcelomaurin/CHATGPT`.

## Componentes usados

- `TPythonConnector`
- `TYOLO`
- `TCHATGPT`

A contagem objetiva é feita pelo `TYOLO`. O `TCHATGPT` é opcional e recebe **somente os números já calculados**, para redigir um resumo textual sem modificar a contagem.

## Pré-requisitos

Instale no Lazarus, a partir da biblioteca CHATGPT:

- `openai_core.lpk`
- `openai_python.lpk`

No Python usado pela aplicação:

```bash
pip install ultralytics
```

Use um modelo treinado para as classes sanguíneas, por exemplo:

```text
models/blood-seg-v1.pt
```

## Uso

1. Abra `hemacias_analyzer.lpi`.
2. Compile.
3. Clique em **Carregar lâmina**.
4. Selecione a fotografia individual obtida do microscópio.
5. Selecione o modelo `.pt`.
6. Ajuste confiança e `imgsz`.
7. Clique em **Analisar**.
8. Confira a contagem e as marcações.
9. Use **Emitir resultado** para JSON, CSV ou TXT.
10. Opcionalmente use **Parecer com IA**.

## Classes

A aplicação normaliza os nomes comuns:

- `hemacia`, `rbc` → Hemácia
- `leucocito`, `wbc` → Leucócito
- `plaqueta`, `platelet` → Plaqueta
- `artefato`, `artifact` → Artefato

Outras classes do modelo continuam aparecendo com o nome fornecido pelo YOLO.

## Importante

Este aplicativo é para pesquisa, teste e desenvolvimento. O resultado automático não deve ser tratado como contagem laboratorial validada ou diagnóstico clínico sem estudo de validação apropriado.


## Integração com o servidor Hemácias

A versão atual também funciona como cliente desktop do gerenciador web.

Fluxo:

```text
Conectar API
  -> carregar protocolos
  -> informar/vincular paciente
  -> criar ou recuperar amostra
  -> carregar configuração da amostra
  -> obter modelo, SHA-256, imgsz e limiares
  -> carregar lâmina
  -> analisar
  -> enviar campo
```

A aplicação valida o SHA-256 do modelo local quando o protocolo possui um modelo cadastrado. Se o arquivo local for diferente, a análise é bloqueada.

O botão **Enviar campo** grava no servidor:

- campo microscópico;
- contagem;
- componentes;
- confiança média;
- detecções individuais;
- bounding boxes;
- polígonos de segmentação quando disponíveis;
- imagem original da lâmina;
- protocolo/modelo;
- origem `LAZARUS`.

### Configuração

Preencha na aplicação:

```text
API URL = https://servidor/hemacias/web
API key = a mesma chave configurada no web/config.php
```

Depois clique em **Conectar**.

### Banco existente

Além das migrações anteriores, execute:

```sql
web/migrations/008_lazarus_source.sql
```

## Segmentação

Quando o modelo Ultralytics retorna máscaras, o `TYOLO` entrega o contorno como pares:

```text
x:y|x:y|x:y|...
```

O analisador desenha esse polígono. Quando não há máscara, mantém o fallback para bounding box.


## Múltiplos campos e qualidade

O desktop agora suporta uma amostra formada por vários campos microscópicos.

Para cada campo:

1. carregue a imagem;
2. o aplicativo calcula a qualidade da imagem;
3. execute a detecção;
4. envie o campo ao servidor;
5. clique em **Novo campo** para continuar.

O controle de qualidade usa os mesmos critérios do módulo Python:

- variância do Laplaciano para foco;
- brilho médio;
- fração de sombras;
- fração de realces;
- coeficiente de variação da iluminação em grade 3×3.

Os estados são:

```text
ACEITA
REVISAR
REJEITADA
```

Campos rejeitados podem ser enviados ao servidor para manter o histórico, porém não entram na consolidação.

## Relatório da amostra

O botão **Relatório amostra** consulta o endpoint `sample_summary` e apresenta:

- campos totais;
- campos válidos;
- rejeitados/excluídos;
- campos para revisão;
- mínimo total exigido pelo protocolo;
- mínimo de campos válidos;
- média;
- mediana;
- mínimo;
- máximo;
- desvio padrão amostral por componente.

Quando o relatório da amostra está sendo exibido, **Emitir resultado** gera um arquivo TXT consolidado. Para um campo individual, continua sendo possível emitir JSON, CSV ou TXT.


## Revisão humana no Lazarus

Depois da análise do campo, o operador pode revisar visualmente as detecções antes de transformar a imagem em ground truth.

Fluxo:

```text
Analisar
  -> clicar sobre uma célula
  -> Trocar classe ou Excluir
  -> opcionalmente Adicionar no clique
  -> Enviar campo
  -> Salvar revisão no dataset
```

A célula selecionada é destacada. Em **Adicionar no clique**, o próximo clique cria uma anotação manual com confiança 1,0, que pode ser posteriormente ajustada ou excluída.

O botão **Salvar revisão no dataset** envia o conjunto revisado ao endpoint `annotations_save`. O servidor:

- valida as classes contra `count_item_types`;
- valida os polígonos e os limites da imagem;
- substitui as anotações anteriores da imagem;
- grava as novas anotações como `MANUAL / APROVADA`;
- registra uma revisão `SAVE_LAZARUS`;
- marca o item do dataset como `REVISADA`.

A revisão altera o ground truth/dataset; ela não reescreve retroativamente a contagem automática original, preservando a rastreabilidade entre predição e correção humana.
