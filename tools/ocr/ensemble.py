"""Cross-reference multiple OCR transcripts and pick the best consensus."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable

from rapidfuzz import fuzz


@dataclass
class OCRCandidate:
    engine: str
    text: str
    lines: list[str]
    confidence: float


def _normalize_line(line: str) -> str:
    line = line.lower().strip()
    line = re.sub(r"\s+", " ", line)
    return line


def _word_like_ratio(text: str) -> float:
    tokens = re.findall(r"[a-zàâäéèêëïîôùûüçñáéíóú0-9]+", text.lower())
    if not tokens:
        return 0.0
    plausible = [t for t in tokens if len(t) >= 2 or t.isdigit()]
    return len(plausible) / len(tokens)


def _garbage_ratio(text: str) -> float:
    if not text:
        return 1.0
    useful = len(re.findall(r"[a-z0-9àâäéèêëïîôùûüçñáéíóú\s.,:;+\-=%()/']", text.lower()))
    return 1.0 - useful / max(1, len(text))


def _quality_score(candidate: OCRCandidate) -> float:
    text = candidate.text
    engine_boost = {
        "chandra": 0.08,
        "surya": 0.07,
        "trocr": 0.06,
        "paddle": 0.05,
        "easyocr": 0.04,
        "vision": 0.075,
    }
    boost = 0.0
    for key, value in engine_boost.items():
        if key in candidate.engine.lower():
            boost = value
            break
    line_score = min(0.2, len(candidate.lines) * 0.018)
    text_score = min(0.16, len(text) / 900)
    word_score = min(0.12, _word_like_ratio(text) * 0.12)
    garbage_penalty = _garbage_ratio(text) * 0.28
    return candidate.confidence * 0.58 + boost + line_score + text_score + word_score - garbage_penalty


def _line_agreement(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    return fuzz.token_sort_ratio(a, b) / 100.0


def _merge_lines(candidates: list[OCRCandidate]) -> list[str]:
    ranked = sorted(candidates, key=_quality_score, reverse=True)
    if not ranked:
        return []
    lines = list(ranked[0].lines)
    for candidate in ranked[1:4]:
        for line in candidate.lines:
            cleaned = _normalize_line(line)
            if len(cleaned) < 2 or _garbage_ratio(cleaned) > 0.38:
                continue
            if not any(_line_agreement(cleaned, existing) > 0.72 for existing in lines):
                lines.append(cleaned)
    return lines


def build_consensus(candidates: Iterable[OCRCandidate]) -> OCRCandidate:
    usable = [c for c in candidates if c.lines]
    if not usable:
        return OCRCandidate(engine="ensemble unavailable", text="", lines=[], confidence=0.12)

    ranked = sorted(usable, key=_quality_score, reverse=True)
    best = ranked[0]
    lines = _merge_lines(ranked)

    agreement_scores: list[float] = []
    for other in ranked[1:4]:
        matches = sum(
            1
            for line in best.lines
            if any(_line_agreement(line, other_line) > 0.72 for other_line in other.lines)
        )
        agreement_scores.append(matches / max(1, len(best.lines)))

    avg_agreement = sum(agreement_scores) / max(1, len(agreement_scores))
    confidence = min(
        0.97,
        max(best.confidence, sum(c.confidence for c in ranked[:3]) / min(3, len(ranked))) + 0.02,
    )
    if avg_agreement < 0.18 and len(lines) >= len(best.lines):
        confidence = min(0.95, confidence + 0.03)

    engines = " + ".join(c.engine for c in ranked[:3])
    return OCRCandidate(
        engine=f"consensus {engines}",
        text="\n".join(lines),
        lines=lines,
        confidence=confidence,
    )


def pick_best(candidates: Iterable[OCRCandidate]) -> OCRCandidate:
    usable = [c for c in candidates if c.lines]
    if not usable:
        return OCRCandidate(engine="ocr unavailable", text="", lines=[], confidence=0.12)
    consensus = build_consensus(usable)
    best_single = max(usable, key=_quality_score)
    if _quality_score(consensus) >= _quality_score(best_single) - 0.02:
        return consensus
    return best_single
