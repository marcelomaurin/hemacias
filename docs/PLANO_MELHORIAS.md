# Plano de melhorias — Hemácias

## Objetivo

Evoluir o projeto de uma prova de conceito de contagem por visão computacional para uma plataforma rastreável de aquisição de imagens, contagem celular, cadastro de pacientes, armazenamento de amostras e validação de resultados.

O sistema deve permanecer explicitamente experimental até que exista validação contra método de referência e critérios laboratoriais definidos.

## Fase 1 — Fundação técnica

1. Modularizar captura, processamento, persistência e interface.
2. Padronizar instalação Python e PHP/MySQL.
3. Criar testes automatizados para o núcleo de processamento.
4. Registrar parâmetros usados em cada contagem: escala, resolução, câmera, método e versão do algoritmo.
5. Manter a imagem original da amostra sem sobrescrita.
6. Criar logs de auditoria para alterações administrativas.

## Fase 2 — Gestão web

Implementar painel PHP/MySQL com:

- autenticação;
- usuários e perfis;
- cadastro de pacientes;
- amostras vinculadas ao paciente;
- múltiplas imagens por amostra;
- múltiplas contagens por amostra;
- componentes sanguíneos identificados;
- escala/magnificação;
- consulta histórica;
- observações e rastreabilidade;
- API autenticada para o aplicativo Python.

## Fase 3 — Contagem robusta

Comparar três abordagens:

1. Hough Circles como baseline;
2. segmentação clássica + morfologia + distance transform + watershed;
3. segmentação supervisionada com as anotações LabelMe existentes.

Medir, no mínimo:

- erro absoluto médio da contagem;
- erro percentual;
- precisão;
- recall;
- F1;
- repetibilidade entre frames;
- taxa de imagens recusadas por qualidade.

## Fase 4 — Qualidade de imagem

Adicionar:

- foco;
- exposição;
- saturação;
- iluminação não uniforme;
- detecção de campo parcial;
- calibração pixel/µm;
- perfis por câmera, microscópio e objetiva.

Uma imagem abaixo do limiar de qualidade deve ser sinalizada em vez de produzir uma contagem silenciosamente.

## Fase 5 — Componentes sanguíneos

O banco e a API devem aceitar componentes genéricos desde o início, por exemplo:

- hemácia;
- leucócito;
- plaqueta;
- outros componentes definidos pela aplicação.

O detector atual identifica somente hemácias. Outros componentes só devem receber identificação automática depois de existir algoritmo validado para eles.

## Fase 6 — Dataset e treinamento

1. Converter LabelMe para um formato padronizado.
2. Separar treino/validação/teste por imagem/campo de origem.
3. Versionar dataset e anotações.
4. Registrar versão do modelo em cada resultado.
5. Não misturar recortes do mesmo campo entre treino e teste.
6. Criar ferramenta de revisão manual de falsos positivos e falsos negativos.

## Fase 7 — Validação

Criar uma base de referência com contagem manual revisada e comparar o sistema em diferentes:

- lâminas;
- concentrações;
- iluminações;
- objetivas;
- câmeras;
- condições de foco.

Somente depois dessa etapa devem ser definidos limites de aceitação.

## Fase 8 — Segurança e LGPD

Como o módulo web armazena dados de pacientes:

- usar HTTPS em produção;
- restringir acesso por usuário;
- aplicar princípio do menor privilégio;
- não colocar dados reais em repositório Git;
- manter backups protegidos;
- registrar acesso/alteração;
- definir política de retenção;
- evitar usar CPF ou outro identificador sensível quando um identificador interno for suficiente.

## Prioridade recomendada

1. Web + banco + API e rastreabilidade.
2. Integração Python com paciente/amostra/resultado.
3. Watershed e calibração.
4. Ferramenta de avaliação.
5. Segmentação treinada.
6. Interface de revisão e relatórios.
7. Validação formal.
