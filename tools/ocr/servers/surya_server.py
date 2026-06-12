"""HTTP server exposing Surya OCR 2 in the format marginalia expects."""

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

from tools.ocr.servers.common import html_to_plain_text, load_image_from_request, surya_page_payload

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("surya_server")

app = Flask(__name__)


@lru_cache(maxsize=1)
def _recognition_predictor():
    surya_root = ROOT / "third_party" / "surya"
    if str(surya_root) not in sys.path:
        sys.path.insert(0, str(surya_root))

    os.environ.setdefault("SURYA_INFERENCE_BACKEND", "llamacpp")
    os.environ.setdefault("SURYA_INFERENCE_KEEP_ALIVE", "1")
    os.environ.setdefault("MODEL_CACHE_DIR", str(Path.home() / ".cache" / "datalab" / "models"))

    from surya.inference import SuryaInferenceManager
    from surya.recognition import RecognitionPredictor

    manager = SuryaInferenceManager()
    return RecognitionPredictor(manager)


def _blocks_from_page(page) -> list[dict]:
    blocks = []
    for index, block in enumerate(page.blocks):
        if getattr(block, "skipped", False):
            continue
        html = getattr(block, "html", "") or ""
        text = html_to_plain_text(html)
        blocks.append(
            {
                "label": getattr(block, "label", "Text"),
                "raw_label": getattr(block, "raw_label", getattr(block, "label", "Text")),
                "reading_order": getattr(block, "reading_order", index),
                "html": html,
                "text": text,
                "confidence": float(getattr(block, "confidence", 0.86) or 0.86),
            }
        )
    return blocks


@app.get("/health")
def health():
    return jsonify({"status": "ok", "engine": "surya-ocr-2"})


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

        predictor = _recognition_predictor()
        pages = predictor([image], full_page=True)
        blocks = _blocks_from_page(pages[0])
        return jsonify(surya_page_payload(blocks))
    except Exception as exc:
        logger.exception("surya ocr failed")
        return jsonify({"error": str(exc)}), 500


def main() -> None:
    port = int(os.environ.get("SURYA_OCR_PORT", "8765"))
    app.run(host="127.0.0.1", port=port, threaded=True)


if __name__ == "__main__":
    main()
