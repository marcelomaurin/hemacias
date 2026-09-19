from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from statistics import mean

import cv2

from hemacias.counter import CellCounter, CounterConfig
from hemacias.watershed import WatershedCounter, WatershedConfig
from hemacias.api_client import HemaciasApiClient


@dataclass(slots=True)
class RowResult:
    image: str
    class_name: str
    manual: int
    automatic: int

    @property
    def absolute_error(self) -> int:
        return abs(self.automatic - self.manual)

    @property
    def percentage_error(self) -> float | None:
        if self.manual == 0:
            return None
        return 100.0 * self.absolute_error / self.manual


def load_reference(path: Path) -> list[tuple[str, str, int]]:
    rows: list[tuple[str, str, int]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        required = {"image", "manual_count"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("CSV deve possuir colunas image,manual_count e opcionalmente class.")
        for row in reader:
            rows.append((
                row["image"],
                (row.get("class") or "hemacia").strip(),
                int(row["manual_count"]),
            ))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compara contagem automática com referência manual."
    )
    parser.add_argument("csv", type=Path, help="CSV com image,manual_count")
    parser.add_argument("--method", choices=("hough", "watershed", "yolo"), default="watershed")
    parser.add_argument("--model", type=Path, help="Modelo .pt para --method yolo")
    parser.add_argument("--confidence", type=float, default=0.25)
    parser.add_argument("--min-radius", type=int, default=15)
    parser.add_argument("--max-radius", type=int, default=35)
    parser.add_argument("--focus", type=float, default=0.0)
    parser.add_argument("--output", type=Path, default=Path("evaluation_results.csv"))
    parser.add_argument("--api-url", help="URL da pasta web para publicar métricas.")
    parser.add_argument("--api-key", help="Chave da API.")
    parser.add_argument("--model-id", type=int, help="ID do modelo cadastrado para receber as métricas.")
    args = parser.parse_args()

    if args.method == "hough":
        detector = CellCounter(
            CounterConfig(
                min_radius=args.min_radius,
                max_radius=args.max_radius,
                min_focus_score=args.focus,
                history_size=1,
            )
        )
    elif args.method == "watershed":
        detector = WatershedCounter(
            WatershedConfig(
                min_radius=args.min_radius,
                max_radius=args.max_radius,
                min_focus_score=args.focus,
                history_size=1,
            )
        )
    else:
        if args.model is None:
            raise SystemExit("--model é obrigatório com --method yolo.")
        from hemacias.yolo_counter import YoloSegCounter
        detector = YoloSegCounter(
            args.model,
            confidence=args.confidence,
            min_focus_score=args.focus,
            history_size=1,
        )

    results: list[RowResult] = []
    base = args.csv.parent

    for image_name, class_name, manual in load_reference(args.csv):
        path = (base / image_name).resolve()
        image = cv2.imread(str(path))
        if image is None:
            print(f"IGNORADA: não foi possível abrir {path}")
            continue

        detector.reset()
        result = detector.detect(image)
        if args.method == "yolo":
            automatic = int(result.counts_by_class.get(class_name, 0))
        else:
            if class_name.casefold() != "hemacia":
                print(
                    f"IGNORADA: {image_name} classe={class_name}; "
                    f"{args.method} não é multiclasse."
                )
                continue
            automatic = result.instant_count

        results.append(RowResult(image_name, class_name, manual, automatic))
        print(
            f"{image_name} [{class_name}]: manual={manual} automático={automatic} "
            f"erro={abs(automatic-manual)}"
        )

    if not results:
        print("Nenhuma imagem avaliada.")
        return 1

    mae = mean(r.absolute_error for r in results)
    percentage_values = [
        r.percentage_error for r in results if r.percentage_error is not None
    ]
    mape = mean(percentage_values) if percentage_values else None
    bias = mean(r.automatic - r.manual for r in results)

    with args.output.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["image", "class", "manual_count", "automatic_count", "absolute_error", "percentage_error"]
        )
        for r in results:
            writer.writerow(
                [
                    r.image,
                    r.class_name,
                    r.manual,
                    r.automatic,
                    r.absolute_error,
                    "" if r.percentage_error is None else f"{r.percentage_error:.4f}",
                ]
            )

    print(f"Linhas avaliadas: {len(results)}")
    print(f"MAE geral: {mae:.3f}")
    print(f"Viés médio geral: {bias:.3f}")
    print("MAPE geral: n/a" if mape is None else f"MAPE geral: {mape:.3f}%")

    classes = sorted({r.class_name for r in results})
    for class_name in classes:
        subset = [r for r in results if r.class_name == class_name]
        class_mae = mean(r.absolute_error for r in subset)
        class_bias = mean(r.automatic - r.manual for r in subset)
        pct = [r.percentage_error for r in subset if r.percentage_error is not None]
        class_mape = mean(pct) if pct else None
        print(
            f"{class_name}: n={len(subset)} MAE={class_mae:.3f} "
            f"viés={class_bias:.3f} "
            + ("MAPE=n/a" if class_mape is None else f"MAPE={class_mape:.3f}%")
        )
    if args.api_url or args.api_key or args.model_id:
        if not (args.api_url and args.api_key and args.model_id):
            raise SystemExit("--api-url, --api-key e --model-id devem ser usados juntos.")
        api = HemaciasApiClient(args.api_url, args.api_key)
        api.upsert_model_metric(
            model_id=args.model_id,
            mae=mae,
            bias=bias,
            mape=mape,
            sample_count=len(results),
            notes=f"Avaliação de contagem: {args.csv.name}",
            metric_origin="COUNT_REFERENCE",
        )
        for class_name in classes:
            subset = [r for r in results if r.class_name == class_name]
            class_mae = mean(r.absolute_error for r in subset)
            class_bias = mean(r.automatic - r.manual for r in subset)
            pct = [r.percentage_error for r in subset if r.percentage_error is not None]
            class_mape = mean(pct) if pct else None
            api.upsert_model_metric(
                model_id=args.model_id,
                component_code=class_name,
                mae=class_mae,
                bias=class_bias,
                mape=class_mape,
                sample_count=len(subset),
                notes=f"Avaliação de contagem: {args.csv.name}",
                metric_origin="COUNT_REFERENCE",
            )
        print(f"Métricas publicadas no modelo #{args.model_id}.")

    print(f"Detalhes: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
