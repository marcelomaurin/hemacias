#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


@dataclass
class MatchStats:
    tp: int = 0
    fp: int = 0
    fn: int = 0
    gt: int = 0
    pred: int = 0
    abs_error_sum: float = 0.0
    bias_sum: float = 0.0
    mape_sum: float = 0.0
    mape_n: int = 0
    image_class_n: int = 0


def api_json(base_url: str, api_key: str, action: str, payload: dict) -> dict:
    url = base_url.rstrip("/") + "/api.php?action=" + urllib.parse.quote(action)
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "X-API-Key": api_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {text}") from exc
    if not data.get("ok"):
        raise RuntimeError(data.get("error", "Falha na API"))
    return data


def parse_class_thresholds(values: list[str], default_iou: float) -> dict[str, float]:
    out: dict[str, float] = {}
    for item in values:
        if "=" not in item:
            raise ValueError(f"Use classe=valor em --class-iou: {item}")
        code, value = item.split("=", 1)
        v = float(value)
        if not 0.0 < v <= 1.0:
            raise ValueError(f"IoU inválido para {code}: {v}")
        out[code.strip().lower()] = v
    out["__default__"] = default_iou
    return out


def polygon_array(poly) -> np.ndarray:
    arr = np.asarray(poly, dtype=np.float32)
    if arr.ndim != 2 or arr.shape[0] < 3 or arr.shape[1] < 2:
        return np.empty((0, 2), dtype=np.float32)
    return arr[:, :2]


def polygon_iou(poly_a, poly_b) -> float:
    a = polygon_array(poly_a)
    b = polygon_array(poly_b)
    if len(a) < 3 or len(b) < 3:
        return 0.0

    min_x = math.floor(min(float(a[:, 0].min()), float(b[:, 0].min())))
    min_y = math.floor(min(float(a[:, 1].min()), float(b[:, 1].min())))
    max_x = math.ceil(max(float(a[:, 0].max()), float(b[:, 0].max())))
    max_y = math.ceil(max(float(a[:, 1].max()), float(b[:, 1].max())))

    w = max_x - min_x + 3
    h = max_y - min_y + 3
    if w <= 1 or h <= 1:
        return 0.0

    pa = np.round(a - np.array([min_x - 1, min_y - 1], dtype=np.float32)).astype(np.int32)
    pb = np.round(b - np.array([min_x - 1, min_y - 1], dtype=np.float32)).astype(np.int32)

    mask_a = np.zeros((h, w), dtype=np.uint8)
    mask_b = np.zeros((h, w), dtype=np.uint8)
    cv2.fillPoly(mask_a, [pa], 1)
    cv2.fillPoly(mask_b, [pb], 1)

    inter = int(np.count_nonzero(mask_a & mask_b))
    union = int(np.count_nonzero(mask_a | mask_b))
    return inter / union if union else 0.0


def match_class(gt: list[dict], pred: list[dict], threshold: float) -> tuple[int, int, int]:
    candidates: list[tuple[float, int, int]] = []
    for gi, g in enumerate(gt):
        for pi, p in enumerate(pred):
            iou = polygon_iou(g["polygon"], p["polygon"])
            if iou >= threshold:
                candidates.append((iou, gi, pi))
    candidates.sort(reverse=True)

    used_gt: set[int] = set()
    used_pred: set[int] = set()
    tp = 0
    for _iou, gi, pi in candidates:
        if gi in used_gt or pi in used_pred:
            continue
        used_gt.add(gi)
        used_pred.add(pi)
        tp += 1

    fp = len(pred) - tp
    fn = len(gt) - tp
    return tp, fp, fn


def safe_div(num: float, den: float) -> float:
    return num / den if den else 0.0


def metrics_from_stats(s: MatchStats) -> dict:
    precision = safe_div(s.tp, s.tp + s.fp)
    recall = safe_div(s.tp, s.tp + s.fn)
    f1 = safe_div(2 * precision * recall, precision + recall)
    return {
        "tp": s.tp,
        "fp": s.fp,
        "fn": s.fn,
        "gt": s.gt,
        "pred": s.pred,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "mae": safe_div(s.abs_error_sum, s.image_class_n),
        "bias": safe_div(s.bias_sum, s.image_class_n),
        "mape": safe_div(s.mape_sum, s.mape_n) if s.mape_n else None,
        "sample_count": s.image_class_n,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Valida modelo contra anotações humanas revisadas.")
    ap.add_argument("--api-url", required=True)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--model-id", required=True, type=int)
    ap.add_argument("--iou", type=float, default=0.50)
    ap.add_argument("--class-iou", action="append", default=[], metavar="CLASSE=VALOR")
    ap.add_argument("--no-publish", action="store_true")
    ap.add_argument("--json-output")
    args = ap.parse_args()

    if not 0.0 < args.iou <= 1.0:
        ap.error("--iou deve estar entre 0 e 1")

    thresholds = parse_class_thresholds(args.class_iou, args.iou)
    data = api_json(args.api_url, args.api_key, "validation_data", {"model_id": args.model_id})
    images = data.get("images", [])
    if not images:
        print("Nenhuma imagem revisada disponível para esse modelo.", file=sys.stderr)
        return 2

    per_class: dict[str, MatchStats] = defaultdict(MatchStats)
    overall = MatchStats()
    classes_seen: set[str] = set()

    for image in images:
        gt_by: dict[str, list[dict]] = defaultdict(list)
        pred_by: dict[str, list[dict]] = defaultdict(list)

        for item in image.get("ground_truth", []):
            code = str(item.get("class_code", "")).strip().lower()
            if code:
                gt_by[code].append(item)
                classes_seen.add(code)
        for item in image.get("predictions", []):
            code = str(item.get("class_code", "")).strip().lower()
            if code:
                pred_by[code].append(item)
                classes_seen.add(code)

        for code in sorted(set(gt_by) | set(pred_by)):
            gt = gt_by.get(code, [])
            pred = pred_by.get(code, [])
            threshold = thresholds.get(code, thresholds["__default__"])
            tp, fp, fn = match_class(gt, pred, threshold)

            s = per_class[code]
            s.tp += tp
            s.fp += fp
            s.fn += fn
            s.gt += len(gt)
            s.pred += len(pred)
            error = len(pred) - len(gt)
            s.abs_error_sum += abs(error)
            s.bias_sum += error
            s.image_class_n += 1
            if len(gt) > 0:
                s.mape_sum += abs(error) / len(gt) * 100.0
                s.mape_n += 1

            overall.tp += tp
            overall.fp += fp
            overall.fn += fn
            overall.gt += len(gt)
            overall.pred += len(pred)
            overall.abs_error_sum += abs(error)
            overall.bias_sum += error
            overall.image_class_n += 1
            if len(gt) > 0:
                overall.mape_sum += abs(error) / len(gt) * 100.0
                overall.mape_n += 1

    class_metrics = {code: metrics_from_stats(per_class[code]) for code in sorted(classes_seen)}
    overall_metrics = metrics_from_stats(overall)

    report = {
        "model": data.get("model"),
        "reviewed_images": len(images),
        "iou_threshold": args.iou,
        "class_iou": {k: v for k, v in thresholds.items() if k != "__default__"},
        "overall": overall_metrics,
        "classes": class_metrics,
    }

    print(json.dumps(report, ensure_ascii=False, indent=2))

    if args.json_output:
        p = Path(args.json_output)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if not args.no_publish:
        for code, m in class_metrics.items():
            api_json(
                args.api_url,
                args.api_key,
                "model_metric_upsert",
                {
                    "model_id": args.model_id,
                    "component_code": code,
                    "metric_origin": "GROUND_TRUTH",
                    "precision": m["precision"],
                    "recall": m["recall"],
                    "f1": m["f1"],
                    "mae": m["mae"],
                    "bias": m["bias"],
                    "mape": m["mape"],
                    "sample_count": m["sample_count"],
                    "notes": f"Validação contra ground truth revisado; IoU={thresholds.get(code, args.iou):.3f}",
                },
            )

        api_json(
            args.api_url,
            args.api_key,
            "model_metric_upsert",
            {
                "model_id": args.model_id,
                "metric_origin": "GROUND_TRUTH",
                "precision": overall_metrics["precision"],
                "recall": overall_metrics["recall"],
                "f1": overall_metrics["f1"],
                "mae": overall_metrics["mae"],
                "bias": overall_metrics["bias"],
                "mape": overall_metrics["mape"],
                "sample_count": len(images),
                "notes": f"Validação micro em {len(images)} imagens revisadas; IoU padrão={args.iou:.3f}",
            },
        )

        run = api_json(
            args.api_url,
            args.api_key,
            "validation_run_register",
            {
                "model_id": args.model_id,
                "iou_threshold": args.iou,
                "reviewed_images": len(images),
                "total_gt": overall_metrics["gt"],
                "total_predictions": overall_metrics["pred"],
                "tp": overall_metrics["tp"],
                "fp": overall_metrics["fp"],
                "fn": overall_metrics["fn"],
                "precision": overall_metrics["precision"],
                "recall": overall_metrics["recall"],
                "f1": overall_metrics["f1"],
                "mae": overall_metrics["mae"],
                "bias": overall_metrics["bias"],
                "mape": overall_metrics["mape"],
                "class_metrics": class_metrics,
                "config": {
                    "default_iou": args.iou,
                    "class_iou": {k: v for k, v in thresholds.items() if k != "__default__"},
                    "matching": "greedy_descending_polygon_iou_same_class",
                },
                "notes": "Gerado por tools/evaluate_reviewed_annotations.py",
            },
        )
        print(f"Validação publicada. validation_run_id={run.get('validation_run_id')}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
