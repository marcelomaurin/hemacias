"""
Script utilitario para enumeracao e captura de imagens de microscopio/camera via OpenCV.
Utilizado pela aplicacao Lazarus via TPythonConnector.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    import cv2
except ImportError:
    print(json.dumps({"ok": False, "error": "OpenCV (cv2) nao instalado"}))
    sys.exit(1)


def list_cameras(max_test: int = 6) -> list[dict]:
    cameras = []
    # No Windows, cv2.CAP_DSHOW eh mais rapido e confiavel para webcam/microscopios USB
    backend = cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY

    for idx in range(max_test):
        cap = cv2.VideoCapture(idx, backend)
        if cap.isOpened():
            # Tenta ler largura e altura padrao ou sugerida
            w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            cap.release()
            cameras.append({
                "index": idx,
                "name": f"Camera {idx}",
                "width": w if w > 0 else 1920,
                "height": h if h > 0 else 1080
            })
    return cameras


def capture_frame(camera_idx: int, width: int | None, height: int | None, output_path: str) -> dict:
    backend = cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY
    cap = cv2.VideoCapture(camera_idx, backend)

    if not cap.isOpened():
        return {"ok": False, "error": f"Nao foi possivel abrir a camera {camera_idx}"}

    try:
        if width and width > 0:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        if height and height > 0:
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

        # Descarta primeiros frames para estabilizar exposicao/auto-white-balance da camera
        for _ in range(5):
            cap.grab()

        ret, frame = cap.read()
        if not ret or frame is None or frame.size == 0:
            return {"ok": False, "error": "Falha ao capturar frame da camera"}

        out_file = Path(output_path).resolve()
        out_file.parent.mkdir(parents=True, exist_ok=True)

        success = cv2.imwrite(str(out_file), frame)
        if not success:
            return {"ok": False, "error": f"Nao foi possivel gravar imagem em {output_path}"}

        h, w = frame.shape[:2]
        return {
            "ok": True,
            "output": str(out_file),
            "width": w,
            "height": h
        }
    finally:
        cap.release()


def main():
    parser = argparse.ArgumentParser(description="Captura de camera para microscopia.")
    parser.add_argument("--list", action="store_true", help="Lista cameras disponiveis")
    parser.add_argument("--capture", action="store_true", help="Captura uma imagem")
    parser.add_argument("--camera", type=int, default=0, help="Indice da camera (padrao: 0)")
    parser.add_argument("--width", type=int, default=1920, help="Largura desejada")
    parser.add_argument("--height", type=int, default=1080, help="Altura desejada")
    parser.add_argument("--output", type=str, default="temp/capture.png", help="Arquivo de saida")

    args = parser.parse_args()

    if args.list:
        cams = list_cameras()
        print(json.dumps({"ok": True, "cameras": cams}))
        return 0

    if args.capture:
        res = capture_frame(args.camera, args.width, args.height, args.output)
        print(json.dumps(res))
        return 0 if res.get("ok") else 1

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
