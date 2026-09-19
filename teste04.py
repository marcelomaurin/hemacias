from __future__ import annotations

import argparse
import cv2

from hemacias.camera import list_video_devices, open_camera
from hemacias.counter import CellCounter, CounterConfig


def parse_args():
    parser = argparse.ArgumentParser(
        description="Contador de hemácias por câmera usando OpenCV."
    )
    parser.add_argument("-lv", "--list-videos", action="store_true",
                        help="Lista os dispositivos de vídeo disponíveis.")
    parser.add_argument("-ind", "--index", type=int, default=0,
                        help="Índice da câmera (padrão: 0).")
    parser.add_argument("--min-radius", type=int, default=15,
                        help="Raio mínimo esperado da hemácia em pixels.")
    parser.add_argument("--max-radius", type=int, default=35,
                        help="Raio máximo esperado da hemácia em pixels.")
    parser.add_argument("--min-distance", type=int, default=10,
                        help="Distância mínima entre centros detectados.")
    parser.add_argument("--param1", type=float, default=40.0,
                        help="Limiar superior do Canny usado pelo Hough.")
    parser.add_argument("--param2", type=float, default=20.0,
                        help="Limiar do acumulador do Hough.")
    parser.add_argument("--focus", type=float, default=35.0,
                        help="Foco mínimo aceito antes de contar.")
    parser.add_argument("--history", type=int, default=15,
                        help="Número de frames usados para estabilizar a contagem.")
    parser.add_argument("--width", type=int, default=None,
                        help="Largura opcional da captura.")
    parser.add_argument("--height", type=int, default=None,
                        help="Altura opcional da captura.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.list_videos:
        devices = list_video_devices()
        if not devices:
            print("Nenhum dispositivo de vídeo encontrado.")
            return 1

        print("Dispositivos de vídeo disponíveis:")
        for index, backend in devices:
            print(f"  {index}: {backend}")
        return 0

    config = CounterConfig(
        min_radius=args.min_radius,
        max_radius=args.max_radius,
        min_distance=args.min_distance,
        hough_param1=args.param1,
        hough_param2=args.param2,
        min_focus_score=args.focus,
        history_size=args.history,
    )
    counter = CellCounter(config)

    try:
        cap = open_camera(args.index, args.width, args.height)
    except RuntimeError as exc:
        print(f"Erro: {exc}")
        return 2

    print("Teclas: q = sair | c = zerar histórico/contagem estabilizada")

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("Falha ao capturar frame da câmera.")
                break

            result = counter.detect(frame)
            output = counter.draw(frame, result)
            cv2.putText(
                output,
                "(C) limpar  (Q) sair",
                (max(10, output.shape[1] - 220), 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 255, 0),
                1,
            )
            cv2.imshow("Contador de Hemacias", output)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            if key == ord("c"):
                counter.reset()
    finally:
        cap.release()
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
