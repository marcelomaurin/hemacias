from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(slots=True)
class ImageQualityResult:
    status: str
    score: float
    focus_score: float
    mean_brightness: float
    shadow_fraction: float
    highlight_fraction: float
    illumination_cv: float
    reasons: list[str]

    def as_dict(self) -> dict:
        return {
            "status": self.status,
            "score": round(self.score, 3),
            "focus_score": round(self.focus_score, 3),
            "mean_brightness": round(self.mean_brightness, 3),
            "shadow_fraction": round(self.shadow_fraction, 5),
            "highlight_fraction": round(self.highlight_fraction, 5),
            "illumination_cv": round(self.illumination_cv, 5),
            "reasons": self.reasons,
        }


def evaluate_image_quality(
    frame: np.ndarray,
    *,
    focus_score: float | None = None,
    min_focus: float = 35.0,
) -> ImageQualityResult:
    if frame is None or frame.size == 0:
        raise ValueError("Frame vazio.")

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    focus = (
        float(focus_score)
        if focus_score is not None
        else float(cv2.Laplacian(gray, cv2.CV_64F).var())
    )

    mean_brightness = float(np.mean(gray))
    shadow_fraction = float(np.mean(gray <= 8))
    highlight_fraction = float(np.mean(gray >= 247))

    h, w = gray.shape[:2]
    y_edges = np.linspace(0, h, 4, dtype=int)
    x_edges = np.linspace(0, w, 4, dtype=int)
    tile_means: list[float] = []
    for yi in range(3):
        for xi in range(3):
            tile = gray[y_edges[yi]:y_edges[yi + 1], x_edges[xi]:x_edges[xi + 1]]
            if tile.size:
                tile_means.append(float(np.mean(tile)))

    illumination_cv = (
        float(np.std(tile_means) / max(np.mean(tile_means), 1.0))
        if tile_means
        else 0.0
    )

    reasons: list[str] = []
    penalties = 0.0
    hard_reject = False

    if focus < min_focus:
        reasons.append("foco abaixo do mínimo")
        penalties += 55.0
        hard_reject = True

    if mean_brightness < 35:
        reasons.append("imagem muito escura")
        penalties += 30.0
    elif mean_brightness > 225:
        reasons.append("imagem muito clara")
        penalties += 30.0

    if shadow_fraction > 0.12:
        reasons.append("excesso de pixels escuros/saturados")
        penalties += min(25.0, shadow_fraction * 100.0)

    if highlight_fraction > 0.12:
        reasons.append("excesso de pixels claros/saturados")
        penalties += min(25.0, highlight_fraction * 100.0)

    if illumination_cv > 0.28:
        reasons.append("iluminação muito desigual")
        penalties += min(30.0, illumination_cv * 60.0)

    score = max(0.0, 100.0 - penalties)
    if hard_reject or score < 45:
        status = "REJEITADA"
    elif score < 75 or reasons:
        status = "REVISAR"
    else:
        status = "ACEITA"

    return ImageQualityResult(
        status=status,
        score=score,
        focus_score=focus,
        mean_brightness=mean_brightness,
        shadow_fraction=shadow_fraction,
        highlight_fraction=highlight_fraction,
        illumination_cv=illumination_cv,
        reasons=reasons,
    )
