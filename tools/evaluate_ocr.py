#!/usr/bin/env python3
"""Score OCR transcripts against ground truth text.

Usage:
  python3 tools/evaluate_ocr.py fixtures/ground_truth.txt outputs/ocr.txt
  python3 tools/evaluate_ocr.py fixtures --predictions outputs
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def normalize(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def edit_distance(a: list[str], b: list[str]) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    previous = list(range(len(b) + 1))
    current = [0] * (len(b) + 1)
    for i, lhs in enumerate(a, start=1):
        current[0] = i
        for j, rhs in enumerate(b, start=1):
            cost = 0 if lhs == rhs else 1
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
        previous, current = current, previous
    return previous[-1]


def score_pair(truth: str, prediction: str) -> dict[str, float]:
    truth = normalize(truth)
    prediction = normalize(prediction)
    truth_chars = list(truth)
    prediction_chars = list(prediction)
    truth_words = re.findall(r"\w+|[^\w\s]", truth)
    prediction_words = re.findall(r"\w+|[^\w\s]", prediction)
    cer = edit_distance(truth_chars, prediction_chars) / max(1, len(truth_chars))
    wer = edit_distance(truth_words, prediction_words) / max(1, len(truth_words))
    exact_line_matches = len(set(truth.splitlines()).intersection(set(prediction.splitlines())))
    line_recall = exact_line_matches / max(1, len([line for line in truth.splitlines() if line.strip()]))
    return {
        "cer": cer,
        "wer": wer,
        "line_recall": line_recall,
        "truth_chars": float(len(truth_chars)),
        "prediction_chars": float(len(prediction_chars)),
    }


def print_score(label: str, metrics: dict[str, float]) -> None:
    print(
        f"{label}: "
        f"cer={metrics['cer']:.3f} "
        f"wer={metrics['wer']:.3f} "
        f"line_recall={metrics['line_recall']:.3f} "
        f"truth_chars={int(metrics['truth_chars'])} "
        f"prediction_chars={int(metrics['prediction_chars'])}"
    )


def score_directory(truth_dir: Path, prediction_dir: Path) -> int:
    truth_files = sorted(path for path in truth_dir.iterdir() if path.suffix.lower() in {".txt", ".md"})
    if not truth_files:
        print(f"no .txt or .md truth files found in {truth_dir}")
        return 1
    failures = 0
    totals = {"cer": 0.0, "wer": 0.0, "line_recall": 0.0}
    for truth_path in truth_files:
        prediction_path = prediction_dir / truth_path.name
        if not prediction_path.exists():
            print(f"missing prediction: {prediction_path}")
            failures += 1
            continue
        metrics = score_pair(truth_path.read_text(), prediction_path.read_text())
        print_score(truth_path.name, metrics)
        for key in totals:
            totals[key] += metrics[key]
    count = max(1, len(truth_files) - failures)
    print(
        f"average: cer={totals['cer'] / count:.3f} "
        f"wer={totals['wer'] / count:.3f} "
        f"line_recall={totals['line_recall'] / count:.3f}"
    )
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("truth", type=Path)
    parser.add_argument("prediction", type=Path, nargs="?")
    parser.add_argument("--predictions", type=Path)
    args = parser.parse_args()

    if args.truth.is_dir():
        prediction_dir = args.predictions or args.prediction
        if prediction_dir is None:
            parser.error("directory mode requires --predictions or a prediction directory")
        return score_directory(args.truth, prediction_dir)

    if args.prediction is None:
        parser.error("file mode requires a prediction file")
    metrics = score_pair(args.truth.read_text(), args.prediction.read_text())
    print_score(args.truth.name, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
