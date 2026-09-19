from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Treina segmentação de hemácias com Ultralytics YOLO."
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=Path("datasets/hemacias_seg/dataset.yaml"),
    )
    parser.add_argument(
        "--model",
        default="yolo26n-seg.pt",
        help="Modelo base Ultralytics de segmentação.",
    )
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--device", default=None, help="Ex.: 0, cpu, 0,1")
    parser.add_argument("--project", default="runs/hemacias")
    parser.add_argument("--name", default="seg")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    if not args.data.exists():
        raise SystemExit(
            f"Dataset não encontrado: {args.data}. "
            "Execute tools/labelme_to_yolo_seg.py primeiro."
        )

    try:
        from ultralytics import YOLO
    except ImportError as exc:
        raise SystemExit(
            "Ultralytics não instalado. Execute: pip install -r requirements-ml.txt"
        ) from exc

    model = YOLO(args.model)
    kwargs = dict(
        data=str(args.data),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        project=args.project,
        name=args.name,
        workers=args.workers,
    )
    if args.device:
        kwargs["device"] = args.device

    results = model.train(**kwargs)
    print("Treino concluído.")
    print(f"Resultados: {getattr(results, 'save_dir', 'consulte runs/')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
