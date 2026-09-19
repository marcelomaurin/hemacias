# Auditoria inicial do dataset

## Situação encontrada no repositório

| Conjunto | Imagens | JSON LabelMe | Cobertura anotada |
|---|---:|---:|---:|
| positivas cinza treino | 60 | 57 | 95,0% |
| positivas cinza testes | 25 | 0 | 0,0% |
| positivas coloridas treino | 60 | 0 | 0,0% |
| positivas coloridas testes | 25 | 0 | 0,0% |

No conjunto **positivas cinza treino**, estas imagens não possuem JSON com o mesmo nome:

- imagem01.jpg
- imagem04.jpg
- imagem26.jpg

Também foi confirmada uma inconsistência concreta: **imagem02.json** contém
`imagePath: "imagem01.jpg"`, embora pelo nome do arquivo a anotação esteja associada a
`imagem02.jpg`.

O conversor LabelMe → YOLO já prioriza a imagem com o mesmo nome-base do JSON, mas a anotação de origem ainda deve ser corrigida para preservar a rastreabilidade.

## Consequência para o treinamento

Neste momento, apenas **positivas cinza treino** possui rótulos utilizáveis para treinamento supervisionado.

Os diretórios chamados de **testes** não possuem ground truth de segmentação. Eles podem ser usados para inspeção visual e inferência qualitativa, mas não para medir precisão, recall, F1 ou qualidade de segmentação enquanto não forem anotados independentemente.

As imagens coloridas também ainda não possuem polígonos LabelMe no repositório.

## Ferramenta adicionada

Execute:

```bash
python tools/audit_dataset.py
```

Ela gera `dataset_audit.json` e atualiza `docs/DATASET_AUDIT.md`.

A auditoria verifica pares imagem/JSON, inconsistência de imagePath, classes, tipos de forma, polígonos inválidos, pontos fora das dimensões e cobertura de anotação.

## Próxima rodada de anotação

1. Corrigir imagePath inconsistentes nos JSONs.
2. Anotar imagem01, imagem04 e imagem26 ou justificar sua exclusão.
3. Criar um conjunto de teste com ground truth independente.
4. Não colocar no teste recortes derivados do mesmo campo usado no treino.
5. Anotar parte das imagens coloridas se o modelo final trabalhar com cor.
6. Rodar a auditoria antes de cada treinamento.
