from __future__ import annotations

import argparse
import tempfile
from pathlib import Path

import cv2

from hemacias.camera import list_video_devices, open_camera
from hemacias.counter import CellCounter, CounterConfig
from hemacias.api_client import HemaciasApiClient


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
    parser.add_argument("--api-url", help="URL da pasta web, ex.: https://servidor/hemacias/web")
    parser.add_argument("--api-key", help="Chave definida em web/config.php")
    parser.add_argument("--patient-name", help="Nome do paciente")
    parser.add_argument("--patient-external-id", help="Identificador externo do paciente")
    parser.add_argument("--birth-date", help="Nascimento AAAA-MM-DD")
    parser.add_argument("--sex", help="Sexo/descrição")
    parser.add_argument("--document", help="Documento/identificador opcional")
    parser.add_argument("--sample-code", help="Código da amostra")
    parser.add_argument("--scale-label", default="40x", help="Escala/objetiva registrada")
    parser.add_argument("--magnification", type=float, default=40.0, help="Magnificação")
    parser.add_argument("--pixel-size-um", type=float, default=None, help="Tamanho de pixel calibrado em µm")
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

    api = None
    sample_id = None
    if args.api_url or args.api_key:
        if not args.api_url or not args.api_key:
            print("Erro: --api-url e --api-key devem ser informados juntos.")
            return 3

        patient_name = args.patient_name or input("Nome do paciente: ").strip()
        patient_external_id = args.patient_external_id or input("Identificador externo do paciente (opcional): ").strip() or None
        sample_code = args.sample_code or input("Código da amostra: ").strip()

        if not patient_name or not sample_code:
            print("Erro: paciente e código da amostra são obrigatórios.")
            return 3

        api = HemaciasApiClient(args.api_url, args.api_key)
        try:
            patient_id = api.upsert_patient(
                name=patient_name,
                external_id=patient_external_id,
                birth_date=args.birth_date,
                sex=args.sex,
                document=args.document,
            )
            sample_id = api.create_sample(
                patient_id=patient_id,
                sample_code=sample_code,
            )
            print(f"Paciente {patient_id} / amostra {sample_id} vinculados ao servidor.")
        except RuntimeError as exc:
            print(f"Erro ao preparar registro remoto: {exc}")
            return 4

    try:
        cap = open_camera(args.index, args.width, args.height)
    except RuntimeError as exc:
        print(f"Erro: {exc}")
        return 2

    print("Teclas: q = sair | c = zerar histórico | s = salvar contagem e imagem no servidor")

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
            if key == ord("s"):
                if api is None or sample_id is None:
                    print("API não configurada. Use --api-url e --api-key para registrar resultados.")
                    continue
                temp_path = None
                try:
                    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
                        temp_path = Path(tmp.name)
                    if not cv2.imwrite(str(temp_path), frame):
                        raise RuntimeError("Falha ao criar imagem temporária.")

                    result_api = api.create_count(
                        sample_id=sample_id,
                        components=[
                            {
                                "code": "hemacia",
                                "name": "Hemácia",
                                "quantity": result.stable_count,
                                "unit": "células/campo",
                            }
                        ],
                        image_path=temp_path,
                        method="opencv-hough",
                        algorithm_version="1.1",
                        scale_label=args.scale_label,
                        magnification=args.magnification,
                        pixel_size_um=args.pixel_size_um,
                        focus_score=result.focus_score,
                        image_quality=result.image_quality,
                        total_cells=result.stable_count,
                    )
                    print(
                        f"Contagem registrada: id={result_api.get('count_id')} "
                        f"imagem={result_api.get('image_id')}"
                    )
                except RuntimeError as exc:
                    print(f"Erro ao enviar contagem: {exc}")
                finally:
                    if temp_path is not None:
                        temp_path.unlink(missing_ok=True)
    finally:
        cap.release()
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
