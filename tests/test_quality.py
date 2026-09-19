import numpy as np

from hemacias.quality import evaluate_image_quality


def test_quality_rejects_low_focus():
    frame = np.full((120, 120, 3), 120, dtype=np.uint8)
    result = evaluate_image_quality(frame, focus_score=1.0, min_focus=35.0)
    assert result.status == "REJEITADA"
    assert "foco abaixo do mínimo" in result.reasons


def test_quality_flags_dark_image():
    frame = np.full((120, 120, 3), 10, dtype=np.uint8)
    result = evaluate_image_quality(frame, focus_score=100.0, min_focus=35.0)
    assert result.status in {"REVISAR", "REJEITADA"}
    assert "imagem muito escura" in result.reasons


def test_quality_flags_bright_image():
    frame = np.full((120, 120, 3), 245, dtype=np.uint8)
    result = evaluate_image_quality(frame, focus_score=100.0, min_focus=35.0)
    assert result.status in {"REVISAR", "REJEITADA"}
    assert "imagem muito clara" in result.reasons


def test_quality_accepts_balanced_image():
    rng = np.random.default_rng(123)
    base = rng.normal(128, 25, size=(180, 180)).clip(30, 225).astype(np.uint8)
    frame = np.stack([base, base, base], axis=-1)
    result = evaluate_image_quality(frame, focus_score=120.0, min_focus=35.0)
    assert result.status == "ACEITA"
    assert result.score >= 75
