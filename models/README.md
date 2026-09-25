# Modelos de Analise Sanguinea (Hemacias)

Este diretorio contem os modelos treinados e otimizados para segmentacao e deteccao de celulas sanguineas (hemacias / eritrocitos) em microscopia optica.

## Modelos Disponiveis

| Arquivo | Descricao | Tamanho | SHA-256 |
|---|---|---|---|
| `blood-seg-v1.pt` | Modelo padrao de segmentacao de hemacias (YOLOv8n-seg ajustado no dataset real) | 6.42 MB | `c3f60f55353165e2a60f2c2fe6b391805869487791f8763a4d2ad8c871b7f647` |
| `best.pt` | Alias identico para o melhor checkpoint de segmentacao | 6.42 MB | `c3f60f55353165e2a60f2c2fe6b391805869487791f8763a4d2ad8c871b7f647` |
| `blood-seg-v1.onnx` | Modelo exportado em formato ONNX (opset 19, slimmed) para maxima portabilidade | 12.55 MB | `8dd96ae3aad1bcd790b3d938f4ebb02d5630799cc8753ff2a9408bc62e436108` |
| `yolov8n-seg.pt` | Pesos base de arquitetura de segmentacao YOLOv8 Nano | 6.74 MB | `a7cd8f929e1903d78a12a48efecab430209f18dc46cb96c3599a5980c63c423c` |

## Metricas de Validacao (`blood-seg-v1`)

- **Mascara (Segmentation) mAP@50:** `0.995` (99.5%)
- **Mascara (Segmentation) mAP@50-95:** `0.781`
- **Bounding Box mAP@50:** `0.995`
- **Bounding Box mAP@50-95:** `0.831`
- **Precisao:** `0.989`
- **Recall:** `1.000`

## Integracao

### Lazarus / Hemacias Analyzer
O aplicativo Lazarus busca por padrao o caminho:
```pascal
FEdModel.Text := 'models' + PathDelim + 'blood-seg-v1.pt';
```

### Python CLI
```bash
python teste04.py --method yolo --model models/blood-seg-v1.pt --confidence 0.25
```
