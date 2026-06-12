"""Vision-language adjudicator: cross-references all local OCR engines."""

from __future__ import annotations

import logging
import os
import sys
from functools import lru_cache
from pathlib import Path

from flask import Flask, jsonify, request

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.ocr.ensemble import OCRCandidate, build_consensus, pick_best
from tools.ocr.servers.common import load_image_from_request, vision_payload
from tools.ocr.servers.engines import easyocr as easyocr_engine
from tools.ocr.servers.engines import trocr as trocr_engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vision_adjudicator")

app = Flask(__name__)

DEFAULT_MODEL = os.environ.get("VISION_LANGUAGE_OCR_MODEL", "marginalia-ocr-ensemble-v1")


@lru_cache(maxsize=1)
def _surya_predictor():
    surya_root = ROOT / "third_party" / "surya"
    if str(surya_root) not in sys.path:
        sys.path.insert(0, str(surya_root))
    os.environ.setdefault("SURYA_INFERENCE_BACKEND", "llamacpp")
    os.environ.setdefault("SURYA_INFERENCE_KEEP_ALIVE", "1")
    from surya.inference import SuryaInferenceManager
    from surya.recognition import RecognitionPredictor

    return RecognitionPredictor(SuryaInferenceManager())


@lru_cache(maxsize=1)
def _chandra_manager():
    from chandra.model import InferenceManager

    return InferenceManager(method="hf")


def _surya_candidate(image) -> OCRCandidate | None:
    try:
        from tools.ocr.servers.common import html_to_plain_text

        pages = _surya_predictor()([image], full_page=True)
        lines = []
        confidences = []
        for block in pages[0].blocks:
            if getattr(block, "skipped", False):
                continue
            text = html_to_plain_text(getattr(block, "html", "") or "")
            if text:
                lines.append(text)
                confidences.append(float(getattr(block, "confidence", 0.86) or 0.86))
        if not lines:
            return None
        confidence = sum(confidences) / len(confidences)
        return OCRCandidate(engine="surya", text="\n".join(lines), lines=lines, confidence=confidence)
    except Exception:
        logger.exception("surya adjudication candidate failed")
        return None


def _chandra_candidate(image) -> OCRCandidate | None:
    from chandra.model.schema import BatchInputItem

    from tools.ocr.servers.common import markdown_to_plain_text

    try:
        results = _chandra_manager().generate([BatchInputItem(image=image)], max_output_tokens=8192)
        if not results:
            return None
        page = results[0]
        markdown = getattr(page, "markdown", "") or getattr(page, "raw", "") or ""
        text = markdown_to_plain_text(markdown)
        lines = [line for line in text.splitlines() if line.strip()]
        if not lines:
            return None
        return OCRCandidate(engine="chandra", text=text, lines=lines, confidence=0.9)
    except Exception:
        logger.exception("chandra adjudication candidate failed")
        return None


def _adjudicate(image, prompt: str | None = None) -> OCRCandidate:
    candidates: list[OCRCandidate] = []
    for fn in (_surya_candidate, _chandra_candidate, trocr_engine.recognize, easyocr_engine.recognize):
        result = fn(image)
        if result:
            candidates.append(result)

    if "candidate" in (prompt or "").lower():
        return build_consensus(candidates)
    return pick_best(candidates)


@app.get("/health")
def health():
    return jsonify({"status": "ok", "engine": DEFAULT_MODEL, "mode": "ensemble-adjudicator"})


@app.post("/")
@app.post("/v1/ocr")
@app.post("/v1/chat/completions")
def adjudicate():
    try:
        payload = request.get_json(silent=True) or {}
        image = load_image_from_request(image_base64=payload.get("image_base64"))
        prompt = payload.get("prompt", "")
        model = payload.get("model", DEFAULT_MODEL)
        result = _adjudicate(image, prompt)
        return jsonify(vision_payload(result.lines, model))
    except Exception as exc:
        logger.exception("vision adjudicator failed")
        return jsonify({"error": str(exc)}), 500


def main() -> None:
    port = int(os.environ.get("VISION_LANGUAGE_OCR_PORT", "8767"))
    app.run(host="127.0.0.1", port=port, threaded=True)


if __name__ == "__main__":
    main()
