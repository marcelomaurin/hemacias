from __future__ import annotations

from collections import Counter, defaultdict, deque
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np


@dataclass(slots=True)
class YoloCell:
    id: int
    class_id: int
    class_name: str
    confidence: float
    x: int
    y: int
    radius_px: float
    bbox: tuple[int, int, int, int]
    polygon: list[tuple[float, float]] = field(default_factory=list)

    def as_dict(self) -> dict:
        bx, by, bw, bh = self.bbox
        return {
            "id": self.id,
            "class_id": self.class_id,
            "class_name": self.class_name,
            "confidence": round(self.confidence, 5),
            "x": self.x,
            "y": self.y,
            "radius_px": round(self.radius_px, 3),
            "bbox": {"x": bx, "y": by, "width": bw, "height": bh},
            "polygon": [[round(x, 2), round(y, 2)] for x, y in self.polygon],
        }


@dataclass(slots=True)
class YoloResult:
    instant_count: int
    stable_count: int
    focus_score: float
    image_quality: str
    cells: list[YoloCell] = field(default_factory=list)
    counts_by_class: dict[str, int] = field(default_factory=dict)
    stable_counts_by_class: dict[str, int] = field(default_factory=dict)

    def cells_by_class(self) -> dict[str, list[YoloCell]]:
        grouped: dict[str, list[YoloCell]] = defaultdict(list)
        for cell in self.cells:
            grouped[cell.class_name].append(cell)
        return dict(grouped)


class YoloSegCounter:
    def __init__(
        self,
        model_path: str | Path,
        *,
        confidence: float = 0.25,
        iou: float = 0.70,
        imgsz: int | None = None,
        min_focus_score: float = 35.0,
        history_size: int = 15,
        target_class: str | None = None,
    ):
        try:
            from ultralytics import YOLO
        except ImportError as exc:
            raise RuntimeError(
                "Ultralytics não instalado. Execute: pip install -r requirements-ml.txt"
            ) from exc

        path = Path(model_path)
        if not path.exists():
            raise RuntimeError(f"Modelo YOLO não encontrado: {path}")

        self.model_path = path
        self.model = YOLO(str(path))
        self.confidence = confidence
        self.iou = iou
        self.imgsz = imgsz
        self.min_focus_score = min_focus_score
        self.target_class = target_class.casefold() if target_class else None
        self._history: deque[int] = deque(maxlen=max(1, history_size))
        self._class_history: dict[str, deque[int]] = {}
        self._history_size = max(1, history_size)

    def reset(self) -> None:
        self._history.clear()
        self._class_history.clear()

    @staticmethod
    def focus_score(gray: np.ndarray) -> float:
        return float(cv2.Laplacian(gray, cv2.CV_64F).var())

    def detect(self, frame: np.ndarray) -> YoloResult:
        if frame is None or frame.size == 0:
            raise ValueError("Frame vazio.")

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        focus = self.focus_score(gray)
        if focus < self.min_focus_score:
            stable = int(round(float(np.median(self._history)))) if self._history else 0
            stable_by_class = {
                name: int(round(float(np.median(values)))) if values else 0
                for name, values in self._class_history.items()
            }
            return YoloResult(0, stable, focus, "DESFOCADA", [], {}, stable_by_class)

        predict_kwargs = {
            "source": frame,
            "conf": self.confidence,
            "iou": self.iou,
            "verbose": False,
        }
        if self.imgsz:
            predict_kwargs["imgsz"] = int(self.imgsz)
        predictions = self.model.predict(**predict_kwargs)
        cells: list[YoloCell] = []

        if predictions:
            result = predictions[0]
            names = result.names or {}
            boxes = result.boxes
            masks = result.masks

            if boxes is not None:
                xyxy = boxes.xyxy.cpu().numpy()
                confs = boxes.conf.cpu().numpy()
                classes = boxes.cls.cpu().numpy().astype(int)
                polygons = masks.xy if masks is not None else [None] * len(xyxy)

                next_id = 1
                for box, conf, class_id, polygon in zip(xyxy, confs, classes, polygons):
                    class_name = str(names.get(int(class_id), class_id))
                    if self.target_class and class_name.casefold() != self.target_class:
                        continue

                    x1, y1, x2, y2 = [float(v) for v in box]
                    x = int(round((x1 + x2) / 2.0))
                    y = int(round((y1 + y2) / 2.0))
                    width = max(1.0, x2 - x1)
                    height = max(1.0, y2 - y1)
                    radius = (width + height) / 4.0
                    poly = (
                        [(float(p[0]), float(p[1])) for p in polygon]
                        if polygon is not None
                        else []
                    )

                    cells.append(
                        YoloCell(
                            id=next_id,
                            class_id=int(class_id),
                            class_name=class_name,
                            confidence=float(conf),
                            x=x,
                            y=y,
                            radius_px=radius,
                            bbox=(int(x1), int(y1), int(width), int(height)),
                            polygon=poly,
                        )
                    )
                    next_id += 1

        counts = Counter(cell.class_name for cell in cells)
        count = len(cells)
        self._history.append(count)

        known_classes = set(self._class_history) | set(counts)
        for class_name in known_classes:
            history = self._class_history.setdefault(
                class_name, deque(maxlen=self._history_size)
            )
            history.append(int(counts.get(class_name, 0)))

        stable = int(round(float(np.median(self._history))))
        stable_by_class = {
            name: int(round(float(np.median(values)))) if values else 0
            for name, values in self._class_history.items()
        }
        return YoloResult(
            count,
            stable,
            focus,
            "OK",
            cells,
            dict(counts),
            stable_by_class,
        )

    @staticmethod
    def draw(frame: np.ndarray, result: YoloResult) -> np.ndarray:
        output = frame.copy()
        palette = [
            (0, 255, 0),
            (255, 180, 0),
            (0, 215, 255),
            (0, 0, 255),
            (255, 255, 255),
            (255, 0, 255),
        ]
        class_names = sorted(result.counts_by_class)
        colors = {name: palette[i % len(palette)] for i, name in enumerate(class_names)}

        for cell in result.cells:
            color = colors.get(cell.class_name, (0, 255, 0))
            if len(cell.polygon) >= 3:
                points = np.array(cell.polygon, dtype=np.int32).reshape((-1, 1, 2))
                cv2.polylines(output, [points], True, color, 2)
            else:
                cv2.circle(output, (cell.x, cell.y), max(2, int(cell.radius_px)), color, 2)
            cv2.putText(
                output,
                f"{cell.class_name}:{cell.id} {cell.confidence:.2f}",
                (cell.x + 3, cell.y - 3),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.34,
                color,
                1,
            )

        summary = " | ".join(
            f"{name}:{result.stable_counts_by_class.get(name, 0)}"
            for name in sorted(result.stable_counts_by_class)
        )
        if not summary:
            summary = "sem objetos"

        cv2.putText(
            output,
            f"YOLO | {summary}",
            (10, max(30, output.shape[0] - 15)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (0, 255, 0),
            2,
        )
        cv2.putText(
            output,
            f"Foco: {result.focus_score:.1f} - {result.image_quality}",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 255, 0) if result.image_quality == "OK" else (0, 0, 255),
            2,
        )
        return output
