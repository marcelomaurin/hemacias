"""Experimento legado de pré-processamento.

Mantido para comparação com o algoritmo original. A captura e a liberação
da câmera foram corrigidas; para uso normal prefira teste04.py.
"""

from __future__ import annotations

import argparse
import cv2
import numpy as np

from hemacias.camera import open_camera


def redefine(image: np.ndarray, width: int = 600, height: int = 400) -> np.ndarray:
    return cv2.resize(image, (width, height))


def show_image(title: str, image: np.ndarray) -> None:
    cv2.imshow(title, redefine(image))


def wait_for_quit() -> None:
    while True:
        if cv2.waitKey(20) & 0xFF == ord("q"):
            break


def mascara_invertida(image: np.ndarray) -> np.ndarray:
    binary = cv2.inRange(image, 55, 255)
    return cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)


def fundo_branco(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, binary = cv2.threshold(gray, 127, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    mask = np.full_like(image, 255)
    cv2.drawContours(mask, contours, -1, 0, thickness=cv2.FILLED)
    return cv2.bitwise_and(image, mask)


def preencher(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, binary = cv2.threshold(gray, 240, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    mask = np.zeros_like(gray)
    cv2.drawContours(mask, contours, -1, 255, thickness=cv2.FILLED)
    return cv2.bitwise_and(gray, mask)


def imagem_mascara(color_image: np.ndarray, gray_image: np.ndarray) -> np.ndarray:
    color_gray = cv2.cvtColor(color_image, cv2.COLOR_BGR2GRAY)
    difference = cv2.absdiff(color_gray, gray_image)
    _, binary_mask = cv2.threshold(difference, 128, 255, cv2.THRESH_BINARY)

    output = np.zeros_like(color_image)
    output[binary_mask != 255] = color_image[binary_mask != 255]
    return output


def encontrar_contornos(image: np.ndarray):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, binary = cv2.threshold(gray, 127, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    return contours


def main() -> int:
    parser = argparse.ArgumentParser(description="Experimento legado de processamento.")
    parser.add_argument("--index", type=int, default=0, help="Índice da câmera.")
    args = parser.parse_args()

    try:
        cap = open_camera(args.index)
    except RuntimeError as exc:
        print(f"Erro: {exc}")
        return 1

    try:
        ok, image = cap.read()
        if not ok:
            print("Não foi possível capturar uma imagem.")
            return 2

        blue, _, _ = cv2.split(image)
        mask = mascara_invertida(blue)
        filled_mask = preencher(mask)

        image2 = imagem_mascara(image, filled_mask)
        image3 = fundo_branco(image2)

        contours = encontrar_contornos(image2)
        output = image.copy()
        cv2.drawContours(output, contours, -1, (0, 255, 0), 2)

        show_image("Mascara", image3)
        show_image("Imagem", output)
        print("Pressione q para sair.")
        wait_for_quit()
    finally:
        cap.release()
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
