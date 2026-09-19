from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str]) -> None:
    print("$", " ".join(str(x) for x in cmd))
    completed = subprocess.run(cmd, cwd=ROOT)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pipeline reproduzível de treino e validação do Blood Seg."
    )
    parser.add_argument("--data", type=Path, default=Path("datasets/hemacias_seg/dataset.yaml"))
    parser.add_argument("--base-model", default="yolo26n-seg.pt")
    parser.add_argument("--version", required=True, help="Ex.: v1")
    parser.add_argument("--dataset-ref", required=True, help="Ex.: dataset-2026-09-19-v1")
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=1024)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--device", default=None)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--project", default="runs/hemacias")
    parser.add_argument("--reference-csv", type=Path, help="CSV de referência para MAE/viés/MAPE.")
    parser.add_argument("--confidence", type=float, default=0.25)
    args = parser.parse_args()

    run_name = f"blood-seg-{args.version}"
    train_cmd = [
        sys.executable,
        "tools/train_yolo_seg.py",
        "--data", str(args.data),
        "--model", args.base_model,
        "--epochs", str(args.epochs),
        "--imgsz", str(args.imgsz),
        "--batch", str(args.batch),
        "--workers", str(args.workers),
        "--project", args.project,
        "--name", run_name,
        "--api-url", args.api_url,
        "--api-key", args.api_key,
        "--registry-code", "blood_seg",
        "--registry-name", "Blood Seg",
        "--registry-version", args.version,
        "--dataset-ref", args.dataset_ref,
    ]
    if args.device:
        train_cmd.extend(["--device", args.device])
    run(train_cmd)

    best_path = ROOT / args.project / run_name / "weights" / "best.pt"
    if not best_path.exists():
        raise SystemExit(f"best.pt não encontrado após treinamento: {best_path}")

    if args.reference_csv:
        from hemacias.api_client import HemaciasApiClient

        api = HemaciasApiClient(args.api_url, args.api_key)
        models = api.list_models()
        model = next(
            (
                m for m in models
                if m.get("code") == "blood_seg"
                and m.get("version") == args.version
            ),
            None,
        )
        if not model:
            raise SystemExit("Modelo treinado não apareceu no cadastro da API.")

        eval_cmd = [
            sys.executable,
            "tools/evaluate_counts.py",
            str(args.reference_csv),
            "--method", "yolo",
            "--model", str(best_path),
            "--confidence", str(args.confidence),
            "--output", str(ROOT / args.project / run_name / "count_evaluation.csv"),
            "--api-url", args.api_url,
            "--api-key", args.api_key,
            "--model-id", str(model["id"]),
        ]
        run(eval_cmd)

    print()
    print("Pipeline concluído.")
    print(f"Versão: {args.version}")
    print(f"Dataset: {args.dataset_ref}")
    print(f"Pesos: {best_path}")
    print("Status inicial no cadastro: VALIDACAO")
    print("A aprovação do modelo deve ser feita após revisar as métricas e os resultados.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
