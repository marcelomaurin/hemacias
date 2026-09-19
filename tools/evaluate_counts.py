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


@dataclass(slots=True)
class RowResult:
    image: str
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


def load_reference(path: Path) -> list[tuple[str, int]]:
    rows: list[tuple[str, int]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        required = {"image", "manual_count"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("CSV deve possuir colunas image,manual_count.")
        for row in reader:
            rows.append((row["image"], int(row["manual_count"])))
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

    for image_name, manual in load_reference(args.csv):
        path = (base / image_name).resolve()
        image = cv2.imread(str(path))
        if image is None:
            print(f"IGNORADA: não foi possível abrir {path}")
            continue

        detector.reset()
        result = detector.detect(image)
        results.append(RowResult(image_name, manual, result.instant_count))
        print(
            f"{image_name}: manual={manual} automático={result.instant_count} "
            f"erro={abs(result.instant_count-manual)}"
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
            ["image", "manual_count", "automatic_count", "absolute_error", "percentage_error"]
        )
        for r in results:
            writer.writerow(
                [
                    r.image,
                    r.manual,
                    r.automatic,
                    r.absolute_error,
                    "" if r.percentage_error is None else f"{r.percentage_error:.4f}",
                ]
            )

    print(f"Imagens: {len(results)}")
    print(f"MAE: {mae:.3f}")
    print(f"Viés médio: {bias:.3f}")
    print("MAPE: n/a" if mape is None else f"MAPE: {mape:.3f}%")
    print(f"Detalhes: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
