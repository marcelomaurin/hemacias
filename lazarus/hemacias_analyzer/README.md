# Hemácias Analyzer — Lazarus (AI Suite + Morfometria Óptica & Calibração Metrológica)

Aplicação desktop profissional para análise microscópica, contagem celular multiclasse, calibração óptica física, morfometria individual e populacional de hemácias com PCA invariante à rotação, e cálculo de índices hematológicos clínicos a partir de dados laboratoriais externos.

Utiliza a suíte Lazarus AI do repositório `marcelomaurin/CHATGPT`.

---

## 1. Princípio Fundamental de Calibração e Morfometria

> **Regra Metrológica Central**: Nunca ajustar a escala para fazer a hemácia "dar 7,5 µm". A escala de medição deve derivar estritamente da óptica física (sensor, objetiva, adaptador), da relação de resolução aquisição/análise e, preferencialmente, de uma calibração física com padrão de rastreabilidade (micrômetro de lâmina ou barra de escala). O diâmetro e área celulares resultantes são consequência direta e honesta da medição microscópica.

---

## 2. Conceitos Ópticos e Fórmulas de Escala

### 2.1 Escala Óptica Teórica
Representa a projeção física do sensor no plano focal da amostra sem considerar redimensionamentos digitais posteriores:
$$\text{Escala Teórica (µm/px)} = \frac{\text{Tamanho do Pixel do Sensor (µm)}}{\text{Magnificação da Objetiva} \times \text{Magnificação do Adaptador}}$$

*Nota*: A magnificação da ocular visual **NÃO** faz parte do caminho óptico que chega ao sensor da câmera digital.

### 2.2 Fator de Redimensionamento (Resize) e Escala Efetiva
Se a imagem for adquirida em alta resolução (ex: 3840×2160) e analisada em resolução diferente (ex: 1920×1080):
$$\text{ResizeFactor}_X = \frac{\text{AcquisitionWidth}}{\text{AnalysisWidth}}, \quad \text{ResizeFactor}_Y = \frac{\text{AcquisitionHeight}}{\text{AnalysisHeight}}$$
$$\text{Escala Efetiva}_X = \text{Escala Teórica} \times \text{ResizeFactor}_X$$
$$\text{Escala Efetiva}_Y = \text{Escala Teórica} \times \text{ResizeFactor}_Y$$

### 2.3 Hierarquia de Métodos de Calibração
A escala de medição utilizada na morfometria obedece à seguinte ordem de precedência:
1. `STAGE_MICROMETER` (Calibração física com lâmina micrométrica aferida) — **CALIBRATED**
2. `SCALE_BAR` (Calibração por barra de escala física conhecida na foto) — **CALIBRATED**
3. `MANUAL` (Valor manual aferido pelo operador) — **CALIBRATED**
4. `THEORETICAL` (Estimativa baseada nos parâmetros do sensor e lentes) — **ESTIMATED**
5. `ESTIMATED_REFERENCE` (Referência estimada apenas para visualização provisória) — **ESTIMATED**

---

## 3. Exemplos Práticos de Cálculo de Escala

### Exemplo 1: Escala Teórica Pura (sem resize)
- Tamanho de pixel do sensor: $3,45\,\mu\text{m}$
- Objetiva: $40\times$
- Adaptador de câmera: $1,0\times$
- Resolução de aquisição e análise: $1920 \times 1080$ ($ResizeFactor = 1,0$)
- **Escala Teórica**:
  $$\frac{3,45}{40 \times 1,0} = 0,08625\,\mu\text{m/pixel}$$

### Exemplo 2: Escala Efetiva com Redimensionamento Digital
- Câmera em $4\text{K}$ Ultra HD: aquisição de $3840 \times 2160$ pixels
- Imagem enviada para inferência e análise: $1920 \times 1080$ pixels
- Fator de redimensionamento:
  $$ResizeFactor = \frac{3840}{1920} = 2,0$$
- **Escala Efetiva**:
  $$0,08625 \times 2,0 = 0,17250\,\mu\text{m/pixel}$$

### Exemplo 3: Calibração Metrológica Real (Micrômetro de Lâmina)
- Linha traçada sobre marcações da lâmina padrão: $1813{,}0\text{ pixels}$
- Distância física padrão correspondente: $100{,}0\,\mu\text{m}$
- **Escala Calibrada**:
  $$\frac{100{,}0\,\mu\text{m}}{1813{,}0\text{ px}} = 0,05516\,\mu\text{m/pixel}$$
- **Classificação de Confiabilidade**: `CALIBRATED` (aprovada para morfometria quantitativa).

---

## 4. Morfometria Celular Rigorosa

1. **Área Física ($A_{\mu m^2}$)** com Suporte a Anisotropia:
   $$A_{\mu m^2} = A_{px} \times \text{Scale}_X \times \text{Scale}_Y$$
2. **Perímetro Físico Ponto a Ponto**:
   Cada segmento do polígono $[(x_i, y_i) \to (x_{i+1}, y_{i+1})]$ tem sua distância física integrada:
   $$P_{\mu m} = \sum \sqrt{(\Delta x \cdot \text{Scale}_X)^2 + (\Delta y \cdot \text{Scale}_Y)^2}$$
3. **Diâmetro Equivalente Físico ($D_{eq}$)**:
   $$D_{eq} = 2 \times \sqrt{\frac{A_{\mu m^2}}{\pi}}$$
4. **Circularidade Bruta e Normalizada**:
   $$\text{RawCircularity} = \frac{4\pi A_{px}}{P_{px}^2}, \quad \text{Circularity} = \min(1.0, \max(0.0, \text{RawCircularity}))$$
   Alertas automáticos são registrados caso $\text{RawCircularity} > 1.05$ (indicando artefato de segmentação do contorno) ou $< 0$.
5. **Eixos Maior e Menor por PCA (Análise de Componentes Principais)**:
   Em vez de aproximar a célula pela bounding box cartesiana, calcula-se a matriz de covariância $2 \times 2$ dos vértices do contorno celular. Os autovetores determinam os eixos intrínsecos de dispersão, tornando o cálculo **totalmente invariante à rotação da hemácia** (0°, 30°, 45°, 90°).
6. **Origem da Geometria (`GeometrySource`)**:
   - `POLYGON`: contorno segmentado real (utilizado nas médias populacionais).
   - `MASK`: máscara binária de alta precisão.
   - `BOUNDING_BOX_ESTIMATE`: estimativa provisória por caixa delimitadora quando o contorno poligonal for insuficiente. Células nessa condição são contabilizadas no total detectado, mas recebem `MeasurementValid = False` e são **excluídas das estatísticas morfométricas científicas**.

---

## 5. Banco de Dados e Migrações

- `web/migrations/011_optical_profiles_and_measurements.sql`: Tabelas iniciais de perfis ópticos, medições e dados hematológicos.
- `web/migrations/012_optical_scale_refinement.sql`: Campos de resolução de aquisição/análise, fatores de resize, escala anisotrópica $X/Y$, circularidade bruta, fonte da geometria e snapshots completos de calibração.

---

## 6. Aviso Científico e Ético

> **AVISO CIENTÍFICO**: O método `THEORETICAL` **NÃO substitui a calibração física por micrômetro de lâmina** para morfometria quantitativa. Lentes de microscópios, tubos e adaptadores C-mount apresentam tolerâncias de fabricação e variações de parfocalidade que podem alterar a escala real em 5% a 20%.
>
> Para laudos e estudos científicos quantitativos, utilize sempre o método `STAGE_MICROMETER` ou `SCALE_BAR` (`CALIBRATED`).
