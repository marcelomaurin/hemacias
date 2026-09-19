import cv2
import numpy as np

from hemacias.counter import CellCounter, CounterConfig


def test_reset_clears_history():
    counter = CellCounter(CounterConfig(min_focus_score=0, history_size=3))
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    counter.detect(frame)
    counter.reset()
    assert len(counter._history) == 0


def test_config_adjusts_even_blur_kernel():
    config = CounterConfig(blur_kernel=10)
    config.validate()
    assert config.blur_kernel == 11


def test_empty_frame_rejected():
    counter = CellCounter()
    try:
        counter.preprocess(np.array([], dtype=np.uint8))
    except ValueError:
        return
    raise AssertionError("Frame vazio deveria gerar ValueError.")
