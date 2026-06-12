"""Shared helpers for marginalia local OCR HTTP servers."""

from __future__ import annotations

import base64
import io
import re
from html import unescape
from typing import Any

from PIL import Image


def load_image_from_request(
    *,
    file_bytes: bytes | None = None,
    image_base64: str | None = None,
) -> Image.Image:
    if file_bytes:
        return Image.open(io.BytesIO(file_bytes)).convert("RGB")
    if image_base64:
        payload = image_base64
        if "," in payload:
            payload = payload.split(",", 1)[1]
        raw = base64.b64decode(payload)
        return Image.open(io.BytesIO(raw)).convert("RGB")
    raise ValueError("image required")


def html_to_plain_text(html: str) -> str:
    text = unescape(html or "")
    text = re.sub(r"</tr>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</p>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</t[dh]>", " | ", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip().lower()


def markdown_to_plain_text(markdown: str) -> str:
    text = markdown or ""
    text = re.sub(r"!\[[^\]]*\]\([^\)]*\)", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^\)]*\)", r"\1", text)
    text = re.sub(r"^#{1,6}\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"^\s*[-*•]\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"`", "", text)
    text = re.sub(r"\*\*|__", "", text)
    lines = [line.strip().lower() for line in text.splitlines() if line.strip()]
    return "\n".join(lines)


def lines_from_text(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        line = raw.strip().lower()
        if len(line) >= 1:
            lines.append(line)
    return lines


def surya_page_payload(blocks: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pages": [{"blocks": blocks}]}


def chandra_payload(markdown: str, confidence: float = 0.9) -> dict[str, Any]:
    return {
        "markdown": markdown,
        "text": markdown_to_plain_text(markdown),
        "confidence": confidence,
        "mode": "accurate",
    }


def vision_payload(lines: list[str], model: str) -> dict[str, Any]:
    return {
        "lines": lines,
        "text": "\n".join(lines),
        "model": model,
    }
