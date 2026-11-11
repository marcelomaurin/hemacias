# Hemácias

O Hemácias é um sistema que **conta e mede as células do sangue em imagens de microscópio**. Você coloca a lâmina no microscópio, captura a imagem e o programa localiza as hemácias, os leucócitos e as plaquetas, conta cada tipo e mede o tamanho das células.

![Hemácias Analyzer com uma lâmina analisada](docs/screenshot.PNG)

> **Projeto experimental e educacional.** O resultado não substitui o hemograma feito em laboratório nem a conferência de um profissional habilitado.

## O que ele faz

- **Conta as células** de uma imagem de lâmina, separando hemácias, leucócitos e plaquetas.
- **Captura a imagem direto da câmera** do microscópio, ou abre uma foto já salva.
- **Avisa quando a imagem está ruim** — fora de foco, escura ou clara demais — em vez de contar errado.
- **Mede cada célula** em micrômetros: área, diâmetro e forma.
- **Calibra a escala** com uma régua micrométrica, para que as medidas sejam reais.
- **Calcula os índices do hemograma** (VCM, HCM e CHCM) a partir dos valores do laboratório.
- **Deixa você corrigir** o que o programa errou: trocar o tipo de uma célula, apagar uma marcação falsa ou incluir uma célula que faltou.
- **Gera o relatório** do resultado em arquivo.
- **Guarda o histórico** por paciente e amostra em um painel acessado pelo navegador.

## Como é o programa

### Aplicativo para Windows

**Tela inicial**

![Tela inicial](docs/img/analisador/tela-inicial.png)

**Lâmina carregada, com réguas em micrômetros**

![Lâmina carregada](docs/img/analisador/lamina-carregada.png)

**Aviso de imagem fora de foco**

![Campo recusado pelo controle de qualidade](docs/img/analisador/campo-rejeitado.png)

**Calibração da escala com régua**

![Calibração por régua](docs/img/analisador/calibracao-regua.png)

**Medidas de cada célula**

![Morfometria](docs/img/analisador/morfometria.png)

**Índices do hemograma**

![Dados clínicos](docs/img/analisador/dados-clinicos.png)

**Ajustes de brilho, contraste e cor**

![Ajustes de imagem](docs/img/analisador/ajustes-imagem.png)

**Correção manual das células**

![Revisão manual](docs/img/analisador/revisao-manual.png)

**Relatório da amostra**

![Relatório da amostra](docs/img/analisador/relatorio-amostra.png)

### Painel no navegador

**Painel inicial**

![Dashboard](docs/img/web/dashboard.png)

**Pacientes**

![Pacientes](docs/img/web/pacientes.png)

**Amostra, com contagens e imagens**

![Amostra](docs/img/web/amostra.png)

**Resultado consolidado da amostra**

![Análise da amostra](docs/img/web/analise-amostra.png)

**Marcação das células na imagem**

![Anotação](docs/img/web/anotacao.png)

**Organização das imagens para treinar o programa**

![Dataset](docs/img/web/dataset.png)

As telas usam um paciente e uma amostra fictícios, criados só para esta página.

## Saiba mais

| Documento | Conteúdo |
|---|---|
| [Instalação](docs/INSTALACAO.md) | Como instalar o aplicativo, o Python e o painel do navegador |
| [Manual do usuário](docs/MANUAL_USUARIO.md) | Como usar cada tela, passo a passo |
| [Guia técnico](docs/GUIA_TECNICO.md) | Para quem desenvolve ou treina os modelos |

O artigo que deu origem ao projeto está em <https://maurinsoft.com.br/projeto-contagem-de-hemacias/>.

## Autor

Marcelo Maurin Martins — [maurinsoft.com.br](https://maurinsoft.com.br)

## Licença

O projeto ainda não tem licença definida.
