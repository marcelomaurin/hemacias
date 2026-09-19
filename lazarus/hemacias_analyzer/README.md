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
