"""Contador de hemácias por visão computacional."""

from .counter import CellCounter, CounterConfig, DetectionResult
from .watershed import WatershedCounter, WatershedConfig, WatershedResult, SegmentedCell

__all__ = [
    "CellCounter",
    "CounterConfig",
    "DetectionResult",
    "WatershedCounter",
    "WatershedConfig",
    "WatershedResult",
    "SegmentedCell",
]
