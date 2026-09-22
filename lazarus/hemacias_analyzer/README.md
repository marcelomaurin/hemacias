# Hemácias Analyzer — Lazarus (AI Suite + Morfometria Óptica)

Aplicação desktop profissional para análise microscópica, contagem celular multiclasse, calibração óptica física, morfometria individual e populacional de hemácias, e cálculo de índices hematológicos clínicos a partir de dados laboratoriais externos.

Utiliza a suíte Lazarus AI do repositório `marcelomaurin/CHATGPT`.

---

## 1. Funcionalidades Principais

1. **Pipeline Unificado de Entrada**:
   - **Arquivo**: carregamento de fotografias microscópicas do disco (`.png`, `.jpg`, `.jpeg`, `.bmp`, `.webp`).
   - **Câmera ao Vivo**: detecção de dispositivos USB/DShow e captura direta de quadros do microscópio óptico.
2. **Sistema de Calibração Óptica**:
   - Perfis ópticos por objetiva: `10x`, `20x`, `40x (padrão)`, `100x (imersão)` ou `Personalizada`.
   - Parâmetros físicos: magnificação do adaptador de câmera e tamanho do pixel do sensor (ex: 3,45 µm).
   - Cálculo automático da escala teórica: $\text{escala} = \frac{\text{pixel\_sensor}}{\text{objetiva} \times \text{adaptador}}$.
   - **Calibração por Régua Micrométrica**: seleção de 2 pontos na lâmina padrão com cálculo preciso em $\mu m/\text{pixel}$ ($D_{px} = \sqrt{\Delta x^2 + \Delta y^2}$; $\text{escala} = \text{dist\_um} / D_{px}$).
3. **Morfometria Individual e Populacional**:
   - **Área** (Shoelace Formula em pixels e $\mu m^2$).
   - **Perímetro** (soma euclidiana de vértices ou elipse de Ramanujan em pixels e $\mu m$).
   - **Diâmetro Equivalente** ($D_{eq} = 2\sqrt{A/\pi}$ em pixels e $\mu m$).
   - **Circularidade** ($4\pi A / P^2$, onde 1.0 = círculo perfeito).
   - **Eixos Maior e Menor** e razão de aspecto.
   - **Filtro de Células de Borda**: detecção automática de hemácias seccionadas nas margens da imagem. As medições individuais são preservadas, mas excluídas das estatísticas populacionais para não distorcer a distribuição de tamanho.
   - **Estatísticas Populacionais**: Média, Desvio Padrão, Mediana, Mínimo, Máximo, Percentis P10, P25, P75, P90.
   - **CV do Diâmetro Microscópico**: Coeficiente de variação geométrica das hemácias na lâmina ($DP / \text{Média} \times 100$). **Nota**: Representa a dispersão microscópica local e não deve ser rotulado como o RDW clínico laboratorial.
4. **Camadas Visuais (Overlays)**:
   - Alternância independente de **Contornos** (polígonos YOLO), **IDs** numéricos das células e **Diâmetros** calculados em $\mu m$.
   - **Barra de Escala Dinâmica**: renderizada no canto da imagem com calibração automática ($5, 10, 20, 50, 100\,\mu m$).
5. **Módulo de Índices Hematológicos Clínicos**:
   - Entrada de parâmetros externos obtidos de contador hematológico automatizado:
     - **Hemácias (RBC)** em $10^6/\mu L$
     - **Hemoglobina (Hb)** em $g/dL$
     - **Hematócrito (Hct)** em $\%$
   - Cálculo rigoroso conforme fórmulas clínicas oficiais de Wintrobe:
     - $\text{VCM} = \frac{\text{Hct} \times 10}{\text{RBC}}\,(fL)$ (Ref: 80 - 100 fL)
     - $\text{HCM} = \frac{\text{Hb} \times 10}{\text{RBC}}\,(pg)$ (Ref: 27 - 32 pg)
     - $\text{CHCM} = \frac{\text{Hb} \times 100}{\text{Hct}}\,(g/dL)$ (Ref: 32 - 36 g/dL)
   - **Aviso Metodológico**: O sistema nunca infere hemoglobina ou VCM clínico a partir de geometria 2D de microscopia óptica.
6. **Revisão Humana e Dataset Ground Truth**:
   - Correção interativa de classes, exclusão de falso-positivos e adição manual de células ausentes com recálculo automático da morfometria.
   - Persistência das anotações revisadas no dataset web para retreinamento supervisionado.
7. **Integração Web API e Banco de Dados**:
   - Envio do campo microscópico contendo o snapshot óptico completo, medições individuais de todas as células e resumo morfométrico.
   - Migração de banco `011_optical_profiles_and_measurements.sql` com tabelas `optical_profiles`, `cell_measurements` e `sample_hematology`.

---

## 2. Requisitos e Compilação

- **Lazarus 3.x** / **Free Pascal 3.2.2** x86_64
- Pacotes instalados no Lazarus (localizados em `CHATGPT/pacote/packages`):
  - `openai_core.lpk`
  - `openai_python.lpk`
- Ambiente Python com dependências:
  ```bash
  pip install ultralytics opencv-python numpy
  ```

### Compilação via lazbuild:
```bash
lazbuild --build-mode=Default "P:\maurinsoft\hemacias\lazarus\hemacias_analyzer\hemacias_analyzer.lpi"
```

---

## 3. Estrutura dos Arquivos Pascal Adicionados

| Arquivo | Descrição |
|---|---|
| `measurement_types.pas` | Tipos de dados para perfis ópticos, medições celulares individuais, estatísticas de morfometria e dados hematológicos clínicos. |
| `morphometry.pas` | Algoritmos de cálculo de área (Shoelace), perímetro, diâmetro equivalente, circularidade, eixos, percentis (QuickSelect), desvio padrão e índices de dispersão. |
| `calibration.pas` | Cálculo de escala teórica e calibração por micrômetro de lâmina de 2 pontos. |
| `camera_service.pas` | Integração Pascal com `camera_capture.py` para detecção de câmeras conectadas e captura de quadros. |
| `camera_capture.py` | Utilitário CLI Python para enumeração e captura de câmeras via OpenCV. |

---

## 4. Banco de Dados

Aplicar a migração:
```text
web/migrations/011_optical_profiles_and_measurements.sql
```

Ela adiciona:
- Tabela `optical_profiles`: armazena configurações de microscópios e calibrações de escala.
- Tabela `cell_measurements`: armazena área, perímetro, diâmetro equivalente, circularidade e status de borda de cada célula analisada.
- Tabela `sample_hematology`: armazena dados laboratoriais externos (RBC, Hb, Hct, VCM, HCM, CHCM).
- Colunas de snapshot óptico na tabela `counts`.

---

## 5. Disclaimer Ético e Científico

Este software é destinado a fins de pesquisa, automação e suporte laboratorial.
O coeficiente de variação do diâmetro celular microscópico calculado sobre imagens 2D não é equivalente e não substitui o índice clínico RDW gerado por contadores hematológicos automatizados. Nenhum resultado automatizado dispensa a validação de um profissional habilitado.
