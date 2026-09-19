from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def parse_class_names(dataset_yaml: Path) -> dict[int, str]:
    names: dict[int, str] = {}
    in_names = False
    for raw in dataset_yaml.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if line.strip() == "names:":
            in_names = True
            continue
        if in_names:
            if line and not line.startswith((" ", "\t")):
                break
            stripped = line.strip()
            if not stripped or ":" not in stripped:
                continue
            key, value = stripped.split(":", 1)
            try:
                names[int(key.strip())] = value.strip().strip("'\"")
            except ValueError:
                continue
    return names


def image_stems(directory: Path) -> set[str]:
    if not directory.exists():
        return set()
    return {
        p.stem
        for p in directory.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    }


def label_stems(directory: Path) -> set[str]:
    if not directory.exists():
        return set()
    return {p.stem for p in directory.glob("*.txt") if p.is_file()}


def count_objects(label_dir: Path) -> Counter[int]:
    counts: Counter[int] = Counter()
    if not label_dir.exists():
        return counts
    for path in label_dir.glob("*.txt"):
        for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.strip()
            if not line:
                continue
            parts = line.split()
            try:
                class_id = int(parts[0])
            except (ValueError, IndexError):
                raise ValueError(f"Label inválido em {path}:{line_no}")
            if len(parts) < 7 or (len(parts) - 1) % 2 != 0:
                raise ValueError(
                    f"Segmentação inválida em {path}:{line_no}: esperado class_id + pares x y."
                )
            counts[class_id] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verifica prontidão estrutural/científica de dataset YOLO Seg."
    )
    parser.add_argument(
        "dataset",
        type=Path,
        help="dataset.yaml ou diretório que contém dataset.yaml.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exige TEST, cobertura de classes em VAL/TEST e proveniência por paciente.",
    )
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    yaml_path = args.dataset if args.dataset.is_file() else args.dataset / "dataset.yaml"
    if not yaml_path.exists():
        raise SystemExit(f"dataset.yaml não encontrado: {yaml_path}")
    root = yaml_path.parent

    class_names = parse_class_names(yaml_path)
    errors: list[str] = []
    warnings: list[str] = []
    splits: dict[str, dict] = {}

    for split in ("train", "val", "test"):
        images_dir = root / "images" / split
        labels_dir = root / "labels" / split
        images = image_stems(images_dir)
        labels = label_stems(labels_dir)
        objects = count_objects(labels_dir)
        orphan_labels = sorted(labels - images)
        unlabeled_images = sorted(images - labels)

        if orphan_labels:
            errors.append(
                f"{split}: {len(orphan_labels)} label(s) sem imagem correspondente."
            )
        if unlabeled_images:
            warnings.append(
                f"{split}: {len(unlabeled_images)} imagem(ns) sem arquivo de label; "
                "confirme se são negativos intencionais."
            )
        if split in {"train", "val"} and not images:
            errors.append(f"{split}: nenhuma imagem.")
        if args.strict and split == "test" and not images:
            errors.append("test: nenhuma imagem; teste independente é obrigatório em modo estrito.")

        splits[split] = {
            "images": len(images),
            "labels": len(labels),
            "objects": dict(sorted(objects.items())),
            "orphan_labels": orphan_labels,
            "unlabeled_images": unlabeled_images,
        }

    train_objects = Counter({int(k): v for k, v in splits["train"]["objects"].items()})
    for class_id, class_name in sorted(class_names.items()):
        if train_objects.get(class_id, 0) == 0:
            warnings.append(f"classe {class_name} ({class_id}) não possui objetos em TRAIN.")
        for split in ("val", "test"):
            count = int(splits[split]["objects"].get(class_id, 0))
            if count == 0:
                message = f"classe {class_name} ({class_id}) não possui objetos em {split.upper()}."
                if args.strict:
                    errors.append(message)
                else:
                    warnings.append(message)

    manifest_path = root / "manifest.json"
    manifest = None
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        provenance = manifest.get("split_provenance") or {}
        mode = provenance.get("group_mode")
        if mode != "PATIENT":
            message = (
                f"proveniência do split é {mode or 'desconhecida'}; "
                "PATIENT é exigido para validação sem reutilizar o mesmo paciente."
            )
            if args.strict:
                errors.append(message)
            else:
                warnings.append(message)
        if manifest.get("leakage_policy") != "patient_and_sample_must_not_cross_splits":
            warnings.append("manifest não declara política de bloqueio de vazamento paciente/amostra.")
    else:
        message = "manifest.json ausente; não é possível comprovar a proveniência do split."
        if args.strict:
            errors.append(message)
        else:
            warnings.append(message)

    report = {
        "dataset": str(yaml_path),
        "strict": args.strict,
        "classes": class_names,
        "splits": splits,
        "manifest_present": manifest is not None,
        "errors": errors,
        "warnings": warnings,
        "ready": not errors,
    }

    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    print(f"Dataset: {yaml_path}")
    for split, info in splits.items():
        total_objects = sum(info["objects"].values())
        print(
            f"{split.upper()}: imagens={info['images']} labels={info['labels']} "
            f"objetos={total_objects}"
        )
        for class_id, quantity in info["objects"].items():
            print(f"  classe {class_id}: {quantity}")

    for warning in warnings:
        print(f"AVISO: {warning}")
    for error in errors:
        print(f"ERRO: {error}")

    if errors:
        print("PRONTIDÃO: BLOQUEADA")
        return 2

    print("PRONTIDÃO: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
