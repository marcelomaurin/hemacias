from __future__ import annotations

import cv2


def list_video_devices(max_devices: int = 10) -> list[tuple[int, str]]:
    """Lista dispositivos de vídeo acessíveis sem parar no primeiro índice vazio."""
    devices: list[tuple[int, str]] = []

    for index in range(max_devices):
        cap = cv2.VideoCapture(index)
        try:
            if cap.isOpened():
                ok, _ = cap.read()
                if ok:
                    backend = cap.getBackendName() if hasattr(cap, "getBackendName") else "desconhecido"
                    devices.append((index, backend))
        finally:
            cap.release()

    return devices


def open_camera(index: int = 0, width: int | None = None, height: int | None = None):
    """Abre a câmera e aplica resolução opcional."""
    cap = cv2.VideoCapture(index)
    if not cap.isOpened():
        cap.release()
        raise RuntimeError(f"Não foi possível abrir a câmera de índice {index}.")

    if width:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    if height:
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    return cap
