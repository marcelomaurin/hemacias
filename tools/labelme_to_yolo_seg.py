from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from dataclasses import dataclass
from pathlib import Path


IMAGE_SUFFIXES = (".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG")


@dataclass(slots=True)
class ConversionStats:
    annotations: int = 0
    images: int = 0
    polygons: int = 0
    skipped_shapes: int = 0
    missing_images: int = 0


def stable_fraction(value: str) -> float:
    digest = hashlib.sha256(value.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") / float(2**64 - 1)


def find_image(json_path: Path, data: dict) -> Path | None:
    # Prioriza arquivo com o mesmo stem do JSON. Alguns JSONs antigos do
    # repositório têm imagePath inconsistente com o nome real do arquivo.
    for suffix in IMAGE_SUFFIXES:
        candidate = json_path.with_suffix(suffix)
        if candidate.exists():
            return candidate

    image_path = data.get("imagePath")
    if image_path:
        candidate = json_path.parent / Path(str(image_path)).name
        if candidate.exists():
            return candidate

    return None


def normalize_polygon(points: list, width: int, height: int) -> list[float]:
    values: list[float] = []
    for point in points:
        if not isinstance(point, list) or len(point) < 2:
            continue
        x = min(max(float(point[0]) / width, 0.0), 1.0)
        y = min(max(float(point[1]) / height, 0.0), 1.0)
        values.extend([x, y])
    return values


def convert_directory(
    source: Path,
    output: Path,
    *,
    class_names: list[str],
    val_ratio: float,
    force_split: str | None = None,
    allow_imagepath_mismatch: bool = False,
) -> ConversionStats:
    stats = ConversionStats()
    class_map = {name.casefold(): idx for idx, name in enumerate(class_names)}

    for json_path in sorted(source.rglob("*.json")):
        data = json.loads(json_path.read_text(encoding="utf-8"))
        width = int(data.get("imageWidth") or 0)
        height = int(data.get("imageHeight") or 0)
        if width <= 0 or height <= 0:
            continue

        declared_image = Path(str(data.get("imagePath") or "")).name
        if declared_image:
            declared_stem = Path(declared_image).stem.casefold()
            if declared_stem != json_path.stem.casefold() and not allow_imagepath_mismatch:
                print(
                    f"IGNORADA: {json_path} declara imagePath={declared_image}. "
                    "Revise a anotação ou use --allow-imagepath-mismatch."
                )
                stats.skipped_shapes += len(data.get("shapes", []))
                continue

        image_path = find_image(json_path, data)
        if image_path is None:
            stats.missing_images += 1
            continue

        if force_split:
            split = force_split
        else:
            split = "val" if stable_fraction(str(json_path.relative_to(source))) < val_ratio else "train"

        labels: list[str] = []
        for shape in data.get("shapes", []):
            label = str(shape.get("label", "")).strip().casefold()
            class_id = class_map.get(label)
            points = shape.get("points")
            if class_id is None or not isinstance(points, list) or len(points) < 3:
                stats.skipped_shapes += 1
                continue

            polygon = normalize_polygon(points, width, height)
            if len(polygon) < 6:
                stats.skipped_shapes += 1
                continue

            labels.append(
                str(class_id) + " " + " ".join(f"{value:.6f}" for value in polygon)
            )
            stats.polygons += 1

        if not labels:
            continue

        rel_key = hashlib.sha1(str(json_path.relative_to(source)).encode("utf-8")).hexdigest()[:10]
        base_name = f"{json_path.stem}_{rel_key}"
        image_dest = output / "images" / split / f"{base_name}{image_path.suffix.lower()}"
        label_dest = output / "labels" / split / f"{base_name}.txt"
        image_dest.parent.mkdir(parents=True, exist_ok=True)
        label_dest.parent.mkdir(parents=True, exist_ok=True)

        shutil.copy2(image_path, image_dest)
        label_dest.write_text("\n".join(labels) + "\n", encoding="utf-8")
        stats.annotations += 1
        stats.images += 1

    return stats


def write_yaml(output: Path, class_names: list[str]) -> None:
    names = "\n".join(f"  {idx}: {name}" for idx, name in enumerate(class_names))
    yaml = (
        f"path: {output.resolve().as_posix()}\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n"
        "names:\n"
        f"{names}\n"
    )
    (output / "dataset.yaml").write_text(yaml, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Converte polígonos LabelMe para segmentação YOLO."
    )
    parser.add_argument(
        "--train-source",
        type=Path,
        default=Path("fotos/positivas cinza treino"),
        help="Diretório com imagens/JSON LabelMe de treino.",
    )
    parser.add_argument(
        "--test-source",
        type=Path,
        default=Path("fotos/positivas cinza testes"),
        help="Diretório opcional com imagens/JSON LabelMe de teste.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("datasets/hemacias_seg"),
    )
    parser.add_argument("--val-ratio", type=float, default=0.20)
    parser.add_argument(
        "--classes",
        nargs="+",
        default=["hemacia"],
        help="Classes LabelMe aceitas, na ordem dos IDs YOLO.",
    )
    parser.add_argument(
        "--allow-imagepath-mismatch",
        action="store_true",
        help="Permite converter JSON cujo imagePath não corresponde ao nome do JSON.",
    )
    args = parser.parse_args()

    if not 0.0 <= args.val_ratio < 1.0:
        raise SystemExit("--val-ratio deve estar entre 0 e 1.")

    if args.output.exists():
        print(f"Aviso: arquivos existentes em {args.output} podem ser substituídos.")

    train_stats = convert_directory(
        args.train_source,
        args.output,
        class_names=args.classes,
        val_ratio=args.val_ratio,
        allow_imagepath_mismatch=args.allow_imagepath_mismatch,
    )

    test_stats = ConversionStats()
    if args.test_source.exists():
        test_stats = convert_directory(
            args.test_source,
            args.output,
            class_names=args.classes,
            val_ratio=0.0,
            force_split="test",
            allow_imagepath_mismatch=args.allow_imagepath_mismatch,
        )

    write_yaml(args.output, args.classes)

    print("Conversão concluída.")
    print(
        f"Treino/val: imagens={train_stats.images}, polígonos={train_stats.polygons}, "
        f"formas ignoradas={train_stats.skipped_shapes}, imagens ausentes={train_stats.missing_images}"
    )
    print(
        f"Teste: imagens={test_stats.images}, polígonos={test_stats.polygons}, "
        f"formas ignoradas={test_stats.skipped_shapes}, imagens ausentes={test_stats.missing_images}"
    )
    print(f"Dataset: {args.output / 'dataset.yaml'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
