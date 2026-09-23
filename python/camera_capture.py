"""
Script utilitario para enumeracao e captura de imagens de microscopio/camera via OpenCV.
Utilizado pela aplicacao Lazarus via TPythonConnector.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

# Suprime logs verbosos do OpenCV para nao corromper a saida JSON lida pelo Lazarus
os.environ["OPENCV_LOG_LEVEL"] = "OFF"
os.environ["OPENCV_VIDEOIO_PRIORITY_MSMF"] = "1"

try:
    import cv2
    if hasattr(cv2, "setLogLevel"):
        cv2.setLogLevel(0)
except ImportError:
    print(json.dumps({"ok": False, "error": "OpenCV (cv2) nao instalado"}))
    sys.exit(1)


def get_windows_camera_names() -> list[str]:
    """Obtem nomes amigaveis das cameras via PowerShell no Windows."""
    if os.name != "nt":
        return []
    try:
        import subprocess
        cmd = ["powershell", "-NoProfile", "-Command",
               "Get-PnpDevice -Class Camera | Where-Object { $_.Present -eq $true } | Select-Object -ExpandProperty FriendlyName"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if res.returncode == 0:
            lines = [line.strip() for line in res.stdout.strip().splitlines() if line.strip()]
            return lines
    except Exception:
        pass
    return []


def list_cameras(max_test: int = 6) -> list[dict]:
    cameras = []
    win_names = get_windows_camera_names()
    backends = [cv2.CAP_MSMF, cv2.CAP_DSHOW] if os.name == "nt" else [cv2.CAP_ANY]

    for idx in range(max_test):
        opened = False
        w, h = 0, 0
        for backend in backends:
            cap = cv2.VideoCapture(idx, backend)
            if cap.isOpened():
                w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                cap.release()
                opened = True
                break

        if opened:
            cam_name = win_names[idx] if idx < len(win_names) else f"Camera {idx}"
            cameras.append({
                "index": idx,
                "name": cam_name,
                "width": w if w > 0 else 1920,
                "height": h if h > 0 else 1080
            })
    return cameras


def capture_frame(camera_idx: int, width: int | None, height: int | None, output_path: str) -> dict:
    backends = [cv2.CAP_MSMF, cv2.CAP_DSHOW] if os.name == "nt" else [cv2.CAP_ANY]
    best_frame = None
    last_err = ""

    for backend in backends:
        b_name = "MSMF" if backend == cv2.CAP_MSMF else ("DSHOW" if backend == cv2.CAP_DSHOW else "ANY")
        cap = cv2.VideoCapture(camera_idx, backend)
        if not cap.isOpened():
            last_err = f"Nao foi possivel abrir a camera {camera_idx} com backend {b_name}"
            continue

        try:
            if width and width > 0:
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            if height and height > 0:
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

            # Warm-up adaptativo: le ate 20 frames ate a luminancia do sensor estabilizar
            for i in range(20):
                ret, frame = cap.read()
                if ret and frame is not None and frame.size > 0:
                    best_frame = frame
                    if frame.mean() > 5.0:
                        break
                time.sleep(0.02)

            if best_frame is not None and best_frame.mean() > 2.0:
                break
        finally:
            cap.release()

    if best_frame is None or best_frame.size == 0:
        return {"ok": False, "error": last_err or "Falha ao capturar frame valido da camera"}

    out_file = Path(output_path).resolve()
    out_file.parent.mkdir(parents=True, exist_ok=True)

    success = cv2.imwrite(str(out_file), best_frame)
    if not success:
        return {"ok": False, "error": f"Nao foi possivel gravar imagem em {output_path}"}

    h, w = best_frame.shape[:2]
    return {
        "ok": True,
        "output": str(out_file),
        "width": w,
        "height": h,
        "mean_luminance": round(float(best_frame.mean()), 2)
    }


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
