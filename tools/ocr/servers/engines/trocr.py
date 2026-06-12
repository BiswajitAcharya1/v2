"""Microsoft TrOCR — strong on messy English handwriting."""

from __future__ import annotations

import logging
from functools import lru_cache

from PIL import Image

from tools.ocr.ensemble import OCRCandidate
from tools.ocr.servers.common import lines_from_text

logger = logging.getLogger(__name__)

MODEL_ID = "microsoft/trocr-large-handwritten"


@lru_cache(maxsize=1)
def _load_pipeline():
    import torch
    from transformers import TrOCRProcessor, VisionEncoderDecoderModel

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    processor = TrOCRProcessor.from_pretrained(MODEL_ID)
    model = VisionEncoderDecoderModel.from_pretrained(MODEL_ID).to(device)
    model.eval()
    return processor, model, device


def recognize(image: Image.Image) -> OCRCandidate | None:
    try:
        processor, model, device = _load_pipeline()
        import torch

        pixel_values = processor(image, return_tensors="pt").pixel_values.to(device)
        with torch.inference_mode():
            generated = model.generate(pixel_values, max_new_tokens=256)
        text = processor.batch_decode(generated, skip_special_tokens=True)[0].strip().lower()
        if not text:
            return None
        lines = lines_from_text(text) or [text]
        confidence = min(0.92, max(0.55, 0.62 + len(text) / 500))
        return OCRCandidate(engine="trocr handwritten", text=text, lines=lines, confidence=confidence)
    except Exception:
        logger.exception("trocr failed")
        return None
