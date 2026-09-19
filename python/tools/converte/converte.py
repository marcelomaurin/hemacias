from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def converter_imagens_cinza(
    diretorio_entrada: Path,
    diretorio_saida: Path,
    tamanho: tuple[int, int] = (100, 100),
) -> int:
    """Converte JPG/JPEG/PNG para escala de cinza e gera lista.txt."""
    if not diretorio_entrada.exists():
        raise FileNotFoundError(f"Diretório não encontrado: {diretorio_entrada}")

    diretorio_saida.mkdir(parents=True, exist_ok=True)
    lista = diretorio_saida / "lista.txt"
    convertidas: list[str] = []

    extensoes = {".jpg", ".jpeg", ".png"}
    for caminho_entrada in sorted(diretorio_entrada.iterdir()):
        if not caminho_entrada.is_file() or caminho_entrada.suffix.lower() not in extensoes:
            continue

        caminho_saida = diretorio_saida / caminho_entrada.with_suffix(".jpg").name

        with Image.open(caminho_entrada) as image:
            cinza = image.convert("L")
            redimensionada = cinza.resize(tamanho)
            redimensionada.save(caminho_saida, quality=95)

        convertidas.append(str(caminho_saida))
        print(f"Convertida: {caminho_entrada.name} -> {caminho_saida}")

    lista.write_text(
        "\n".join(convertidas) + ("\n" if convertidas else ""),
        encoding="utf-8",
    )

    return len(convertidas)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Converte imagens do dataset para tons de cinza."
    )
    parser.add_argument("entrada", type=Path, help="Diretório de imagens de entrada.")
    parser.add_argument("saida", type=Path, help="Diretório onde as imagens serão gravadas.")
    parser.add_argument("--width", type=int, default=100)
    parser.add_argument("--height", type=int, default=100)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        total = converter_imagens_cinza(
            args.entrada,
            args.saida,
            (args.width, args.height),
        )
    except (FileNotFoundError, OSError) as exc:
        print(f"Erro: {exc}")
        return 1

    print(f"Finalizado. {total} imagem(ns) convertida(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
