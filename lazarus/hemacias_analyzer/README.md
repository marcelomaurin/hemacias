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
