from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
import math

import cv2
import numpy as np


@dataclass(slots=True)
class WatershedConfig:
    min_radius: int = 15
    max_radius: int = 35
    min_circularity: float = 0.30
    distance_ratio: float = 0.38
    morph_kernel: int = 3
    morph_iterations: int = 1
    min_focus_score: float = 35.0
    history_size: int = 15

    def validate(self) -> None:
        if self.min_radius <= 0:
            raise ValueError("min_radius deve ser maior que zero.")
        if self.max_radius <= self.min_radius:
            raise ValueError("max_radius deve ser maior que min_radius.")
        if not 0.0 < self.distance_ratio < 1.0:
            raise ValueError("distance_ratio deve estar entre 0 e 1.")
        if not 0.0 <= self.min_circularity <= 1.0:
            raise ValueError("min_circularity deve estar entre 0 e 1.")
        if self.morph_kernel < 3:
            self.morph_kernel = 3
        if self.morph_kernel % 2 == 0:
            self.morph_kernel += 1


@dataclass(slots=True)
class SegmentedCell:
    id: int
    x: int
    y: int
    radius_px: float
    area_px: float
    perimeter_px: float
    circularity: float
    bbox: tuple[int, int, int, int]
    confidence: float

    def as_dict(self) -> dict:
        bx, by, bw, bh = self.bbox
        return {
            "id": self.id,
            "x": self.x,
            "y": self.y,
            "radius_px": round(self.radius_px, 3),
            "area_px": round(self.area_px, 3),
            "perimeter_px": round(self.perimeter_px, 3),
            "circularity": round(self.circularity, 4),
            "confidence": round(self.confidence, 4),
            "bbox": {"x": bx, "y": by, "width": bw, "height": bh},
        }


@dataclass(slots=True)
class WatershedResult:
    instant_count: int
    stable_count: int
    focus_score: float
    image_quality: str
    cells: list[SegmentedCell] = field(default_factory=list)
    mask: np.ndarray | None = None


class WatershedCounter:
    """Segmentação clássica para separar objetos celulares adjacentes.

    É um método experimental. O filtro geométrico assume uma faixa de tamanho
    esperada em pixels e deve ser calibrado para câmera, objetiva e resolução.
    """

    def __init__(self, config: WatershedConfig | None = None):
        self.config = config or WatershedConfig()
        self.config.validate()
        self._history: deque[int] = deque(maxlen=self.config.history_size)

    def reset(self) -> None:
        self._history.clear()

    @staticmethod
    def focus_score(gray: np.ndarray) -> float:
        return float(cv2.Laplacian(gray, cv2.CV_64F).var())

    @staticmethod
    def _foreground_ratio(binary: np.ndarray) -> float:
        return float(np.count_nonzero(binary)) / float(binary.size)

    def _binary_mask(self, gray: np.ndarray) -> np.ndarray:
        blur = cv2.GaussianBlur(gray, (5, 5), 0)

        _, normal = cv2.threshold(
            blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
        )
        inverted = cv2.bitwise_not(normal)

        # Escolhe a polaridade cujo primeiro plano ocupa uma fração mais
        # plausível do campo. Isso evita depender rigidamente de fundo claro/escuro.
        candidates = [normal, inverted]
        plausible = [
            (abs(self._foreground_ratio(mask) - 0.35), mask)
            for mask in candidates
            if 0.03 <= self._foreground_ratio(mask) <= 0.80
        ]
        binary = min(plausible, key=lambda item: item[0])[1] if plausible else inverted

        kernel = np.ones(
            (self.config.morph_kernel, self.config.morph_kernel), np.uint8
        )
        binary = cv2.morphologyEx(
            binary,
            cv2.MORPH_OPEN,
            kernel,
            iterations=self.config.morph_iterations,
        )
        binary = cv2.morphologyEx(
            binary,
            cv2.MORPH_CLOSE,
            kernel,
            iterations=self.config.morph_iterations,
        )
        return binary

    def detect(self, frame: np.ndarray) -> WatershedResult:
        if frame is None or frame.size == 0:
            raise ValueError("Frame vazio.")

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        focus = self.focus_score(gray)

        if focus < self.config.min_focus_score:
            stable = int(round(float(np.median(self._history)))) if self._history else 0
            return WatershedResult(
                instant_count=0,
                stable_count=stable,
                focus_score=focus,
                image_quality="DESFOCADA",
                cells=[],
                mask=None,
            )

        binary = self._binary_mask(gray)
        kernel = np.ones((3, 3), np.uint8)

        sure_bg = cv2.dilate(binary, kernel, iterations=2)
        distance = cv2.distanceTransform(binary, cv2.DIST_L2, 5)

        if float(distance.max()) <= 0:
            self._history.append(0)
            return WatershedResult(
                instant_count=0,
                stable_count=int(round(float(np.median(self._history)))),
                focus_score=focus,
                image_quality="SEM_OBJETOS",
                cells=[],
                mask=binary,
            )

        _, sure_fg = cv2.threshold(
            distance,
            self.config.distance_ratio * float(distance.max()),
            255,
            0,
        )
        sure_fg = np.uint8(sure_fg)
        unknown = cv2.subtract(sure_bg, sure_fg)

        _, markers = cv2.connectedComponents(sure_fg)
        markers = markers + 1
        markers[unknown == 255] = 0

        ws_frame = frame.copy()
        markers = cv2.watershed(ws_frame, markers)

        min_area = math.pi * (self.config.min_radius ** 2) * 0.45
        max_area = math.pi * (self.config.max_radius ** 2) * 2.20

        cells: list[SegmentedCell] = []
        next_id = 1

        for label in range(2, int(markers.max()) + 1):
            region = np.uint8(markers == label) * 255
            contours, _ = cv2.findContours(
                region, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
            )
            if not contours:
                continue

            contour = max(contours, key=cv2.contourArea)
            area = float(cv2.contourArea(contour))
            if area < min_area or area > max_area:
                continue

            perimeter = float(cv2.arcLength(contour, True))
            if perimeter <= 0:
                continue

            circularity = float(4.0 * math.pi * area / (perimeter * perimeter))
            if circularity < self.config.min_circularity:
                continue

            moments = cv2.moments(contour)
            if moments["m00"] == 0:
                continue

            x = int(round(moments["m10"] / moments["m00"]))
            y = int(round(moments["m01"] / moments["m00"]))
            radius = math.sqrt(area / math.pi)
            bbox = tuple(int(v) for v in cv2.boundingRect(contour))

            radius_mid = (self.config.min_radius + self.config.max_radius) / 2.0
            radius_span = max(1.0, (self.config.max_radius - self.config.min_radius) / 2.0)
            radius_score = max(0.0, 1.0 - abs(radius - radius_mid) / (radius_span * 2.0))
            confidence = max(
                0.0,
                min(1.0, 0.55 * min(circularity, 1.0) + 0.45 * radius_score),
            )

            cells.append(
                SegmentedCell(
                    id=next_id,
                    x=x,
                    y=y,
                    radius_px=radius,
                    area_px=area,
                    perimeter_px=perimeter,
                    circularity=circularity,
                    bbox=bbox,
                    confidence=confidence,
                )
            )
            next_id += 1

        count = len(cells)
        self._history.append(count)
        stable = int(round(float(np.median(self._history))))

        return WatershedResult(
            instant_count=count,
            stable_count=stable,
            focus_score=focus,
            image_quality="OK",
            cells=cells,
            mask=binary,
        )

    @staticmethod
    def draw(frame: np.ndarray, result: WatershedResult) -> np.ndarray:
        output = frame.copy()

        for cell in result.cells:
            cv2.circle(
                output,
                (cell.x, cell.y),
                max(2, int(round(cell.radius_px))),
                (0, 255, 0),
                2,
            )
            cv2.putText(
                output,
                str(cell.id),
                (cell.x + 3, cell.y - 3),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.38,
                (0, 255, 0),
                1,
            )

        cv2.putText(
            output,
            f"Hemacias: {result.stable_count} (frame: {result.instant_count})",
            (10, max(30, output.shape[0] - 15)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (0, 255, 0),
            2,
        )
        cv2.putText(
            output,
            f"Watershed | Foco: {result.focus_score:.1f} - {result.image_quality}",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 255, 0) if result.image_quality == "OK" else (0, 0, 255),
            2,
        )
        return output
