"""PaddleOCR multilingual engine — strong on printed + some handwriting."""

from __future__ import annotations

import logging
from functools import lru_cache

from PIL import Image

from tools.ocr.ensemble import OCRCandidate
from tools.ocr.servers.common import lines_from_text

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _load_ocr():
    from paddleocr import PaddleOCR

    return PaddleOCR(
        use_angle_cls=True,
        lang="multi",
        show_log=False,
        use_gpu=False,
    )


def recognize(image: Image.Image) -> OCRCandidate | None:
    try:
        import numpy as np

        ocr = _load_ocr()
        results = ocr.ocr(np.array(image), cls=True)
        lines: list[str] = []
        confidences: list[float] = []
        for page in results or []:
            for item in page or []:
                if not item or len(item) < 2:
                    continue
                text_info, score = item[1]
                cleaned = str(text_info).strip().lower()
                if cleaned:
                    lines.append(cleaned)
                    confidences.append(float(score))
        if not lines:
            return None
        text = "\n".join(lines)
        confidence = min(0.88, max(0.42, sum(confidences) / len(confidences)))
        return OCRCandidate(engine="paddleocr multilingual", text=text, lines=lines_from_text(text), confidence=confidence)
    except Exception:
        logger.exception("paddleocr unavailable on this platform")
        return None
