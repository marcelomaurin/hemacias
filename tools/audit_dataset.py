from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}

@dataclass(slots=True)
class AuditResult:
    directory: str
    images: int = 0
    annotations: int = 0
    images_without_json: list[str] = field(default_factory=list)
    json_without_image: list[str] = field(default_factory=list)
    imagepath_mismatch: list[dict] = field(default_factory=list)
    invalid_shapes: list[dict] = field(default_factory=list)
    out_of_bounds_points: list[dict] = field(default_factory=list)
    classes: Counter = field(default_factory=Counter)
    shape_types: Counter = field(default_factory=Counter)
    polygons: int = 0
    total_points: int = 0

    @property
    def annotated_ratio(self) -> float:
        return 0.0 if self.images == 0 else self.annotations / self.images

def image_files(directory: Path) -> list[Path]:
    return sorted(p for p in directory.iterdir()
                  if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES)

def audit_directory(directory: Path) -> AuditResult:
    result = AuditResult(directory=str(directory))
    if not directory.exists():
        return result

    images = image_files(directory)
    jsons = sorted(directory.glob("*.json"))
    result.images = len(images)
    result.annotations = len(jsons)

    image_by_stem = {p.stem.casefold(): p for p in images}
    json_by_stem = {p.stem.casefold(): p for p in jsons}

    result.images_without_json = [
        p.name for p in images if p.stem.casefold() not in json_by_stem
    ]
    result.json_without_image = [
        p.name for p in jsons if p.stem.casefold() not in image_by_stem
    ]

    for json_path in jsons:
        try:
            data = json.loads(json_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            result.invalid_shapes.append(
                {"file": json_path.name, "reason": f"JSON inválido: {exc}"}
            )
            continue

        width = int(data.get("imageWidth") or 0)
        height = int(data.get("imageHeight") or 0)
        image_path = Path(str(data.get("imagePath") or "")).name

        if image_path and Path(image_path).stem.casefold() != json_path.stem.casefold():
            result.imagepath_mismatch.append({
                "file": json_path.name,
                "imagePath": image_path,
                "expected_stem": json_path.stem,
            })

        for index, shape in enumerate(data.get("shapes") or []):
            label = str(shape.get("label") or "").strip()
            shape_type = str(shape.get("shape_type") or "")
            points = shape.get("points") or []

            result.classes[label] += 1
            result.shape_types[shape_type] += 1
            result.total_points += len(points)
            if shape_type == "polygon":
                result.polygons += 1

            if not label:
                result.invalid_shapes.append(
                    {"file": json_path.name, "shape": index, "reason": "classe vazia"}
                )
            if shape_type != "polygon":
                result.invalid_shapes.append({
                    "file": json_path.name,
                    "shape": index,
                    "reason": f"shape_type={shape_type!r}; esperado 'polygon'",
                })
            if not isinstance(points, list) or len(points) < 3:
                result.invalid_shapes.append({
                    "file": json_path.name,
                    "shape": index,
                    "reason": "polígono com menos de 3 pontos",
                })
                continue

            valid_points = []
            for point in points:
                if (not isinstance(point, list) or len(point) < 2
                        or not all(isinstance(v, (int, float)) and math.isfinite(v)
                                   for v in point[:2])):
                    result.invalid_shapes.append({
                        "file": json_path.name,
                        "shape": index,
                        "reason": "ponto inválido",
                    })
                    continue
                valid_points.append(point)

            if width > 0 and height > 0:
                outside = [
                    [float(p[0]), float(p[1])]
                    for p in valid_points
                    if p[0] < 0 or p[0] > width or p[1] < 0 or p[1] > height
                ]
                if outside:
                    result.out_of_bounds_points.append({
                        "file": json_path.name,
                        "shape": index,
                        "points": outside,
                        "width": width,
                        "height": height,
                    })
    return result

def result_dict(result: AuditResult) -> dict:
    return {
        "directory": result.directory,
        "images": result.images,
        "annotations": result.annotations,
        "annotated_ratio": round(result.annotated_ratio, 4),
        "images_without_json": result.images_without_json,
        "json_without_image": result.json_without_image,
        "imagepath_mismatch": result.imagepath_mismatch,
        "invalid_shapes": result.invalid_shapes,
        "out_of_bounds_points": result.out_of_bounds_points,
        "classes": dict(result.classes),
        "shape_types": dict(result.shape_types),
        "polygons": result.polygons,
        "total_points": result.total_points,
    }

def write_markdown(results: list[AuditResult], path: Path) -> None:
    lines = [
        "# Auditoria do dataset",
        "",
        "Relatório gerado automaticamente por tools/audit_dataset.py.",
        "",
        "## Resumo",
        "",
        "| Diretório | Imagens | JSON | Cobertura | Problemas |",
        "|---|---:|---:|---:|---:|",
    ]
    for r in results:
        problems = (len(r.images_without_json) + len(r.json_without_image)
                    + len(r.imagepath_mismatch) + len(r.invalid_shapes)
                    + len(r.out_of_bounds_points))
        lines.append(
            f"| {r.directory} | {r.images} | {r.annotations} | "
            f"{r.annotated_ratio*100:.1f}% | {problems} |"
        )

    for r in results:
        lines.extend(["", f"## {r.directory}", ""])
        lines.append(f"- Imagens: **{r.images}**")
        lines.append(f"- Anotações JSON: **{r.annotations}**")
        lines.append(f"- Cobertura: **{r.annotated_ratio*100:.1f}%**")
        lines.append(f"- Classes: {dict(r.classes)}")
        lines.append(f"- Tipos de forma: {dict(r.shape_types)}")
        lines.append(f"- Polígonos: **{r.polygons}**")

        if r.images_without_json:
            lines += ["", "### Imagens sem JSON"]
            lines += [f"- {name}" for name in r.images_without_json]
        if r.json_without_image:
            lines += ["", "### JSON sem imagem correspondente"]
            lines += [f"- {name}" for name in r.json_without_image]
        if r.imagepath_mismatch:
            lines += ["", "### imagePath inconsistente"]
            for item in r.imagepath_mismatch:
                lines.append(
                    f"- {item['file']} aponta para {item['imagePath']} "
                    f"(esperado stem {item['expected_stem']})."
                )
        if r.invalid_shapes:
            lines += ["", "### Formas inválidas"]
            lines += [f"- {item}" for item in r.invalid_shapes]
        if r.out_of_bounds_points:
            lines += ["", "### Pontos fora da imagem"]
            lines += [f"- {item}" for item in r.out_of_bounds_points]

    lines += [
        "",
        "## Interpretação",
        "",
        "Somente imagens com anotação válida devem entrar em treino/validação supervisionados.",
        "Imagens sem anotação podem ser usadas para inferência qualitativa, mas não como ground truth.",
        "Um conjunto de teste supervisionado precisa possuir rótulos independentes.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")

def main() -> int:
    parser = argparse.ArgumentParser(description="Audita dataset LabelMe do projeto.")
    parser.add_argument(
        "directories",
        nargs="*",
        type=Path,
        default=[
            Path("fotos/positivas cinza treino"),
            Path("fotos/positivas cinza testes"),
            Path("fotos/positivas coloridas treino"),
            Path("fotos/positivas coloridas testes"),
        ],
    )
    parser.add_argument("--json-output", type=Path, default=Path("dataset_audit.json"))
    parser.add_argument("--markdown-output", type=Path, default=Path("docs/DATASET_AUDIT.md"))
    args = parser.parse_args()

    results = [audit_directory(directory) for directory in args.directories]
    args.json_output.write_text(
        json.dumps([result_dict(r) for r in results], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
    write_markdown(results, args.markdown_output)

    for r in results:
        problems = (len(r.images_without_json) + len(r.json_without_image)
                    + len(r.imagepath_mismatch) + len(r.invalid_shapes)
                    + len(r.out_of_bounds_points))
        print(
            f"{r.directory}: {r.images} imagens, {r.annotations} JSON, "
            f"{r.annotated_ratio*100:.1f}% anotado, {problems} ocorrência(s)."
        )
    print(f"JSON: {args.json_output}")
    print(f"Markdown: {args.markdown_output}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
