from __future__ import annotations

import argparse
import hashlib
from datetime import datetime
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
    parser.add_argument("--api-url", help="URL da pasta web para registrar o modelo treinado.")
    parser.add_argument("--api-key", help="Chave da API.")
    parser.add_argument("--registry-code", default="blood_seg", help="Código do modelo no cadastro.")
    parser.add_argument("--registry-name", default="Blood Seg", help="Nome do modelo no cadastro.")
    parser.add_argument("--registry-version", help="Versão do modelo, ex.: v1.")
    parser.add_argument("--dataset-ref", help="Identificação/versionamento do dataset.")
    args = parser.parse_args()

    if not args.data.exists():
        raise SystemExit(
            f"Dataset não encontrado: {args.data}. "
            "Execute tools/labelme_to_yolo_seg.py primeiro."
        )

    dataset_root = args.data.parent
    train_labels = list((dataset_root / "labels" / "train").glob("*.txt"))
    val_labels = list((dataset_root / "labels" / "val").glob("*.txt"))
    if not train_labels:
        raise SystemExit("Treinamento bloqueado: não há labels em labels/train.")
    if not val_labels:
        raise SystemExit(
            "Treinamento bloqueado: não há labels em labels/val. "
            "A validação é obrigatória para este projeto."
        )

    print(f"Labels de treino: {len(train_labels)}")
    print(f"Labels de validação: {len(val_labels)}")

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
    save_dir = Path(str(getattr(results, "save_dir", Path(args.project) / args.name)))
    best_path = save_dir / "weights" / "best.pt"
    print("Treino concluído.")
    print(f"Resultados: {save_dir}")

    if args.api_url or args.api_key or args.registry_version:
        if not (args.api_url and args.api_key and args.registry_version):
            raise SystemExit(
                "--api-url, --api-key e --registry-version devem ser usados juntos "
                "para registrar o treinamento."
            )
        if not best_path.exists():
            raise SystemExit(f"Treino concluído, mas best.pt não foi encontrado: {best_path}")

        sha = hashlib.sha256()
        with best_path.open("rb") as fp:
            for chunk in iter(lambda: fp.read(1024 * 1024), b""):
                sha.update(chunk)

        try:
            import yaml
            data_info = yaml.safe_load(args.data.read_text(encoding="utf-8")) or {}
            names = data_info.get("names", {})
            if isinstance(names, dict):
                classes = [str(names[k]) for k in sorted(names, key=lambda x: int(x))]
            elif isinstance(names, list):
                classes = [str(x) for x in names]
            else:
                classes = []
        except Exception:
            classes = []

        from hemacias.api_client import HemaciasApiClient
        api = HemaciasApiClient(args.api_url, args.api_key)
        model_id = api.register_model(
            code=args.registry_code,
            name=args.registry_name,
            version=args.registry_version,
            file_path=str(best_path),
            sha256=sha.hexdigest(),
            dataset_ref=args.dataset_ref or str(args.data),
            imgsz=args.imgsz,
            epochs=args.epochs,
            classes=classes,
            status="VALIDACAO",
            trained_at=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            notes=f"Treinado automaticamente por tools/train_yolo_seg.py; base={args.model}",
        )

        metrics = getattr(results, "results_dict", {}) or {}
        api.upsert_model_metric(
            model_id=model_id,
            precision=float(metrics.get("metrics/precision(B)", 0.0)) if "metrics/precision(B)" in metrics else None,
            recall=float(metrics.get("metrics/recall(B)", 0.0)) if "metrics/recall(B)" in metrics else None,
            map50=float(metrics.get("metrics/mAP50(B)", 0.0)) if "metrics/mAP50(B)" in metrics else None,
            map5095=float(metrics.get("metrics/mAP50-95(B)", 0.0)) if "metrics/mAP50-95(B)" in metrics else None,
            notes="Métricas globais retornadas pelo treinamento Ultralytics.",
        )
        print(f"Modelo registrado para validação: #{model_id} · {args.registry_code} {args.registry_version}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
