"""HTTP server exposing Chandra OCR 2 in the format marginalia expects."""

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

from tools.ocr.ensemble import OCRCandidate, pick_best
from tools.ocr.servers.common import chandra_payload, load_image_from_request, markdown_to_plain_text
from tools.ocr.servers.engines import easyocr as easyocr_engine
from tools.ocr.servers.engines import trocr as trocr_engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chandra_server")

app = Flask(__name__)


@lru_cache(maxsize=1)
def _chandra_model():
    os.environ.setdefault("MODEL_CHECKPOINT", "datalab-to/chandra-ocr-2")
    os.environ.setdefault("MODEL_CACHE_DIR", str(Path.home() / ".cache" / "datalab" / "models"))

    from chandra.model import InferenceManager
    from chandra.model.hf import HFInference

    manager = InferenceManager(method="hf")
    return manager


def _run_chandra(image) -> OCRCandidate | None:
    try:
        from chandra.model.schema import BatchInputItem

        manager = _chandra_model()
        results = manager.generate([BatchInputItem(image=image)], max_output_tokens=8192)
        if not results:
            return None
        page = results[0]
        markdown = getattr(page, "markdown", "") or getattr(page, "raw", "") or ""
        text = markdown_to_plain_text(markdown)
        lines = [line for line in text.splitlines() if line.strip()]
        confidence = float(getattr(page, "confidence", 0.9) or 0.9)
        return OCRCandidate(engine="chandra ocr", text=text, lines=lines, confidence=confidence)
    except Exception:
        logger.exception("chandra hf inference failed")
        return None


def _ensemble(image) -> OCRCandidate:
    candidates: list[OCRCandidate] = []
    chandra = _run_chandra(image)
    if chandra:
        candidates.append(chandra)
    trocr = trocr_engine.recognize(image)
    if trocr:
        candidates.append(trocr)
    easy = easyocr_engine.recognize(image)
    if easy:
        candidates.append(easy)
    return pick_best(candidates)


@app.get("/health")
def health():
    return jsonify({"status": "ok", "engine": "chandra-ocr-2-ensemble"})


@app.post("/")
@app.post("/ocr")
@app.post("/v1/ocr")
def ocr():
    try:
        image = None
        if request.files.get("file"):
            image = load_image_from_request(file_bytes=request.files["file"].read())
        elif request.is_json:
            payload = request.get_json(silent=True) or {}
            image = load_image_from_request(image_base64=payload.get("image_base64"))
        if image is None:
            return jsonify({"error": "file or image_base64 required"}), 400

        result = _ensemble(image)
        markdown = "\n".join(result.lines)
        payload = chandra_payload(markdown, confidence=result.confidence)
        payload["engine"] = result.engine
        payload["lines"] = result.lines
        return jsonify(payload)
    except Exception as exc:
        logger.exception("chandra server failed")
        return jsonify({"error": str(exc)}), 500


def main() -> None:
    port = int(os.environ.get("CHANDRA_OCR_PORT", "8766"))
    app.run(host="127.0.0.1", port=port, threaded=True)


if __name__ == "__main__":
    main()
