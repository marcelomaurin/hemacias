from __future__ import annotations

import argparse
import tempfile
from pathlib import Path

import cv2

from hemacias.camera import list_video_devices, open_camera
from hemacias.counter import CellCounter, CounterConfig
from hemacias.watershed import WatershedCounter, WatershedConfig
from hemacias.yolo_counter import YoloSegCounter
from hemacias.api_client import HemaciasApiClient
from hemacias.quality import evaluate_image_quality


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
    parser.add_argument("--method", choices=("hough", "watershed", "yolo"), default="watershed",
                        help="Método de detecção (hough, watershed ou yolo).")
    parser.add_argument("--model", help="Arquivo .pt treinado, obrigatório para --method yolo.")
    parser.add_argument("--confidence", type=float, default=0.25, help="Confiança mínima do YOLO.")
    parser.add_argument("--iou", type=float, default=0.70, help="IoU usado pelo YOLO.")
    parser.add_argument("--min-circularity", type=float, default=0.30,
                        help="Circularidade mínima usada pelo watershed.")
    parser.add_argument("--distance-ratio", type=float, default=0.38,
                        help="Separação de centros no watershed (0-1).")
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
    parser.add_argument("--protocol-code", default="sangue_padrao",
                        help="Código do protocolo de contagem cadastrado no servidor.")
    parser.add_argument("--scale-label", default=None, help="Escala/objetiva; usa o protocolo quando omitida.")
    parser.add_argument("--magnification", type=float, default=None, help="Magnificação; usa o protocolo quando omitida.")
    parser.add_argument("--pixel-size-um", type=float, default=None, help="Tamanho de pixel calibrado em µm")
    parser.add_argument("--allow-low-quality-save", action="store_true",
                        help="Permite salvar campo rejeitado pelo controle de qualidade.")
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

    if args.method == "hough":
        counter = CellCounter(
            CounterConfig(
                min_radius=args.min_radius,
                max_radius=args.max_radius,
                min_distance=args.min_distance,
                hough_param1=args.param1,
                hough_param2=args.param2,
                min_focus_score=args.focus,
                history_size=args.history,
            )
        )
    elif args.method == "watershed":
        counter = WatershedCounter(
            WatershedConfig(
                min_radius=args.min_radius,
                max_radius=args.max_radius,
                min_circularity=args.min_circularity,
                distance_ratio=args.distance_ratio,
                min_focus_score=args.focus,
                history_size=args.history,
            )
        )
    else:
        if not args.model:
            print("Erro: --model é obrigatório quando --method yolo.")
            return 5
        try:
            counter = YoloSegCounter(
                args.model,
                confidence=args.confidence,
                iou=args.iou,
                min_focus_score=args.focus,
                history_size=args.history,
            )
        except RuntimeError as exc:
            print(f"Erro ao carregar modelo: {exc}")
            return 5

    api = None
    sample_id = None
    resource_items = {}
    active_protocol = None
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
                protocol_code=args.protocol_code,
            )
            config = api.get_configuration(sample_id=sample_id)
            active_protocol = next(
                (
                    p for p in config.get("protocols", [])
                    if int(config.get("sample", {}).get("protocol_id") or 0)
                    == int(p.get("id") or 0)
                ),
                None,
            )
            protocol_items = (
                active_protocol.get("items", [])
                if active_protocol
                else config.get("items", [])
            )
            resource_items = {
                str(item.get("code", "")).casefold(): item
                for item in protocol_items
                if item.get("code")
            }
            print(
                f"Paciente {patient_id} / amostra {sample_id} vinculados ao servidor"
                + (
                    f" · protocolo {active_protocol.get('name')}"
                    if active_protocol else ""
                )
                + "."
            )
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
            quality = evaluate_image_quality(
                frame,
                focus_score=result.focus_score,
                min_focus=args.focus,
            )
            output = counter.draw(frame, result)
            cv2.putText(
                output,
                f"Qualidade: {quality.status} ({quality.score:.0f})",
                (10, 55),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (0, 255, 0) if quality.status == "ACEITA" else ((0, 215, 255) if quality.status == "REVISAR" else (0, 0, 255)),
                2,
            )
            cv2.putText(
                output,
                "(C) limpar  (S) salvar  (Q) sair",
                (max(10, output.shape[1] - 300), 30),
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
                quality_required = (
                    bool(active_protocol.get("require_quality", True))
                    if active_protocol else True
                )
                if (
                    quality_required
                    and quality.status == "REJEITADA"
                    and not args.allow_low_quality_save
                ):
                    print(
                        "Campo bloqueado pelo controle de qualidade: "
                        + (", ".join(quality.reasons) or "qualidade insuficiente")
                        + ". Use --allow-low-quality-save para exceção explícita."
                    )
                    continue
                if api is None or sample_id is None:
                    print("API não configurada. Use --api-url e --api-key para registrar resultados.")
                    continue
                temp_path = None
                try:
                    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
                        temp_path = Path(tmp.name)
                    if not cv2.imwrite(str(temp_path), frame):
                        raise RuntimeError("Falha ao criar imagem temporária.")

                    if args.method == "yolo":
                        grouped = result.cells_by_class()
                        components = []
                        for class_name, cells in sorted(grouped.items()):
                            code = class_name.casefold()
                            cfg = resource_items.get(code, {})
                            if cfg and not bool(cfg.get("ai_enabled", True)):
                                continue
                            threshold = float(
                                cfg.get("confidence_threshold", args.confidence)
                            )
                            accepted_cells = [
                                cell for cell in cells
                                if cell.confidence >= threshold
                            ]
                            if not accepted_cells:
                                continue
                            confidences = [cell.confidence for cell in accepted_cells]
                            components.append(
                                {
                                    "code": code,
                                    "name": cfg.get("name", class_name),
                                    "quantity": len(accepted_cells),
                                    "unit": cfg.get("default_unit", "objetos/campo"),
                                    "confidence": sum(confidences) / len(confidences),
                                    "metadata": {
                                        "detections": [
                                            cell.as_dict() for cell in accepted_cells
                                        ],
                                        "configured_threshold": threshold,
                                        "raw_detected": len(cells),
                                        "stable_count_displayed": result.stable_counts_by_class.get(
                                            class_name, len(cells)
                                        ),
                                        "method": args.method,
                                        "model": args.model,
                                        "protocol": (
                                            active_protocol.get("code")
                                            if active_protocol else None
                                        ),
                                    },
                                }
                            )
                    else:
                        cfg = resource_items.get("hemacia", {})
                        components = [
                            {
                                "code": "hemacia",
                                "name": cfg.get("name", "Hemácia"),
                                "quantity": result.instant_count,
                                "unit": cfg.get("default_unit", "células/campo"),
                                "metadata": {
                                    "detections": (
                                        [cell.as_dict() for cell in result.cells]
                                        if hasattr(result, "cells")
                                        else [
                                            {"x": x, "y": y, "radius_px": radius}
                                            for x, y, radius in result.circles
                                        ]
                                    ),
                                    "stable_count_displayed": result.stable_count,
                                    "method": args.method,
                                    "protocol": (
                                        active_protocol.get("code")
                                        if active_protocol else None
                                    ),
                                },
                            }
                        ]

                    result_api = api.create_count(
                        sample_id=sample_id,
                        components=components,
                        image_path=temp_path,
                        method=(
                            "opencv-hough"
                            if args.method == "hough"
                            else ("opencv-watershed" if args.method == "watershed" else "yolo-seg")
                        ),
                        algorithm_version="1.5",
                        scale_label=(
                            args.scale_label
                            or (
                                active_protocol.get("default_scale_label")
                                if active_protocol else None
                            )
                            or "40x"
                        ),
                        magnification=(
                            args.magnification
                            if args.magnification is not None
                            else (
                                active_protocol.get("default_magnification")
                                if active_protocol else None
                            )
                            or 40.0
                        ),
                        pixel_size_um=args.pixel_size_um,
                        focus_score=result.focus_score,
                        image_quality=quality.status,
                        quality_score=quality.score,
                        quality_reason="; ".join(quality.reasons) if quality.reasons else None,
                        quality_metrics=quality.as_dict(),
                        total_cells=result.instant_count,
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
