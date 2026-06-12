"""EasyOCR — multilingual fallback (en, fr, es, de, it, pt, and more)."""

from __future__ import annotations

import logging
from functools import lru_cache

from PIL import Image

from tools.ocr.ensemble import OCRCandidate
from tools.ocr.servers.common import lines_from_text

logger = logging.getLogger(__name__)

LANGUAGES = ["en", "fr", "es", "de", "it", "pt", "nl", "pl", "ru", "ar", "hi", "zh_sim", "ja", "ko"]


@lru_cache(maxsize=1)
def _load_reader():
    import easyocr

    return easyocr.Reader(LANGUAGES, gpu=False, verbose=False)


def recognize(image: Image.Image) -> OCRCandidate | None:
    try:
        import numpy as np

        reader = _load_reader()
        results = reader.readtext(np.array(image), detail=1, paragraph=True)
        lines: list[str] = []
        confidences: list[float] = []
        for item in results:
            if len(item) == 3:
                _, text, conf = item
            else:
                text, conf = item[0], item[1]
            cleaned = str(text).strip().lower()
            if cleaned:
                lines.append(cleaned)
                confidences.append(float(conf))
        if not lines:
            return None
        text = "\n".join(lines)
        confidence = min(0.9, max(0.45, sum(confidences) / len(confidences)))
        return OCRCandidate(engine="easyocr multilingual", text=text, lines=lines_from_text(text), confidence=confidence)
    except Exception:
        logger.exception("easyocr failed")
        return None
