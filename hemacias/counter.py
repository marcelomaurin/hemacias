from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
import math

import cv2
import numpy as np


@dataclass(slots=True)
class CounterConfig:
    min_radius: int = 15
    max_radius: int = 35
    min_distance: int = 10
    hough_dp: float = 1.0
    hough_param1: float = 40.0
    hough_param2: float = 20.0
    blur_kernel: int = 9
    clahe_clip_limit: float = 2.0
    clahe_grid_size: int = 8
    min_focus_score: float = 35.0
    history_size: int = 15

    def validate(self) -> None:
        if self.min_radius <= 0:
            raise ValueError("min_radius deve ser maior que zero.")
        if self.max_radius <= self.min_radius:
            raise ValueError("max_radius deve ser maior que min_radius.")
        if self.min_distance <= 0:
            raise ValueError("min_distance deve ser maior que zero.")
        if self.blur_kernel < 3:
            raise ValueError("blur_kernel deve ser >= 3.")
        if self.blur_kernel % 2 == 0:
            self.blur_kernel += 1
        if self.history_size < 1:
            raise ValueError("history_size deve ser >= 1.")


@dataclass(slots=True)
class DetectionResult:
    instant_count: int
    stable_count: int
    focus_score: float
    image_quality: str
    circles: list[tuple[int, int, int]] = field(default_factory=list)


class CellCounter:
    """Detector de hemácias com pré-processamento e estabilização temporal."""

    def __init__(self, config: CounterConfig | None = None):
        self.config = config or CounterConfig()
        self.config.validate()
        self._history: deque[int] = deque(maxlen=self.config.history_size)

    def reset(self) -> None:
        self._history.clear()

    @staticmethod
    def focus_score(gray: np.ndarray) -> float:
        return float(cv2.Laplacian(gray, cv2.CV_64F).var())

    def preprocess(self, frame: np.ndarray) -> np.ndarray:
        if frame is None or frame.size == 0:
            raise ValueError("Frame vazio.")

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        clahe = cv2.createCLAHE(
            clipLimit=self.config.clahe_clip_limit,
            tileGridSize=(self.config.clahe_grid_size, self.config.clahe_grid_size),
        )
        gray = clahe.apply(gray)

        return cv2.GaussianBlur(
            gray,
            (self.config.blur_kernel, self.config.blur_kernel),
            0,
        )

    def detect(self, frame: np.ndarray) -> DetectionResult:
        processed = self.preprocess(frame)
        focus = self.focus_score(processed)

        if focus < self.config.min_focus_score:
            stable = int(round(float(np.median(self._history)))) if self._history else 0
            return DetectionResult(
                instant_count=0,
                stable_count=stable,
                focus_score=focus,
                image_quality="DESFOCADA",
                circles=[],
            )

        circles_raw = cv2.HoughCircles(
            processed,
            cv2.HOUGH_GRADIENT,
            dp=self.config.hough_dp,
            minDist=self.config.min_distance,
            param1=self.config.hough_param1,
            param2=self.config.hough_param2,
            minRadius=self.config.min_radius,
            maxRadius=self.config.max_radius,
        )

        circles: list[tuple[int, int, int]] = []
        if circles_raw is not None:
            rounded = np.rint(circles_raw[0]).astype(int)
            height, width = frame.shape[:2]
            for x, y, radius in rounded:
                if 0 <= x < width and 0 <= y < height and radius > 0:
                    circles.append((int(x), int(y), int(radius)))

        instant_count = len(circles)
        self._history.append(instant_count)
        stable_count = int(round(float(np.median(self._history))))

        return DetectionResult(
            instant_count=instant_count,
            stable_count=stable_count,
            focus_score=focus,
            image_quality="OK",
            circles=circles,
        )

    @staticmethod
    def draw(frame: np.ndarray, result: DetectionResult) -> np.ndarray:
        output = frame.copy()

        for x, y, radius in result.circles:
            cv2.circle(output, (x, y), radius, (0, 255, 0), 2)
            cv2.circle(output, (x, y), 2, (0, 255, 0), -1)

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
            f"Foco: {result.focus_score:.1f} - {result.image_quality}",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (0, 255, 0) if result.image_quality == "OK" else (0, 0, 255),
            2,
        )

        return output
