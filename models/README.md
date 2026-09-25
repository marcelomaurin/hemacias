# Modelos Especializados em Análise Hematológica (Hemácias e Células Sanguíneas)

Este diretório contém os modelos treinados e validados para detecção e contagem celular de esfregaços sanguíneos em microscopia óptica.

---

## 🏆 Modelos Treinados em Células Sanguíneas (Alta Precisão)

### 1. `blood-cell-bccd-yolov8m.pt` (YOLOv8 Medium - 52.0 MB)
* **Dataset:** BCCD (Blood Cell Count and Detection - benchmark internacional de microscopia).
* **Classes:** `RBC` (Hemácias), `WBC` (Leucócitos), `Platelets` (Plaquetas).
* **Capacidade:** 25.9M parâmetros. Máxima precisão e discriminação de células aglomeradas e leucócitos.
* **Uso recomendado:** Diagnóstico detalhado, contagem multiclasse diferencial e alta resolução.

### 2. `blood-cell-bccd-yolov8s.pt` (YOLOv8 Small - 22.5 MB)
* **Dataset:** BCCD (Blood Cell Count and Detection).
* **Classes:** `RBC` (Hemácias), `WBC` (Leucócitos), `Platelets` (Plaquetas).
* **Capacidade:** 11.2M parâmetros.
* **Desempenho:** Equilíbrio perfeito entre velocidade de inferência em CPU (~70 ms) e sensibilidade em campos com alta densidade celular (ex: 46 hemácias detectadas em `amostra_a.png`).

### 3. `blood-cell-bccd-yolov8n.pt` (YOLOv8 Nano - 6.2 MB)
* **Dataset:** BCCD (Blood Cell Count and Detection).
* **Classes:** `RBC` (Hemácias), `WBC` (Leucócitos), `Platelets` (Plaquetas).
* **Uso:** Leve e rápido para câmeras USB em tempo real sem placa de vídeo.

### 4. `blood-seg-v1.pt` / `best.pt` (YOLOv8 Nano Seg - 6.4 MB)
* **Dataset:** Dataset real do projeto (`fotos/positivas cinza treino`).
* **Tarefa:** Segmentação de Instância (máscara poligonal exata da borda celular).
* **Métricas Validadas:**
  * **mAP@50 (Mask):** `0.995` (99.5%)
  * **Precisão:** `0.989` (98.9%)
  * **Recall:** `1.000` (100%)

---

## 💻 Como Usar

### No Aplicativo Lazarus (`Hemacias Analyzer`)
No campo **Modelo**, aponte para:
* `models\blood-cell-bccd-yolov8s.pt` (para detecção multiclasse de hemácias, leucócitos e plaquetas)
* ou `models\blood-seg-v1.pt` (para segmentação poligonal)

### Via Linha de Comando (Python)
```bash
# Detecção multiclasse completa com o modelo Small:
python teste04.py --method yolo --model models/blood-cell-bccd-yolov8s.pt --confidence 0.25

# Detecção com máxima precisão com o modelo Medium:
python teste04.py --method yolo --model models/blood-cell-bccd-yolov8m.pt --confidence 0.25
```
