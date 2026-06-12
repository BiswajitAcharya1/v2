#!/usr/bin/env python3
"""Pre-download all OCR model weights for offline use."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path.home() / ".cache" / "datalab" / "models"
CACHE.mkdir(parents=True, exist_ok=True)
os.environ["MODEL_CACHE_DIR"] = str(CACHE)
os.environ["HF_HOME"] = str(Path.home() / ".cache" / "huggingface")


def _pip_importable(module: str) -> bool:
    try:
        __import__(module)
        return True
    except Exception:
        return False


def download_hf(repo_id: str, *, allow_patterns: list[str] | None = None) -> None:
    from huggingface_hub import snapshot_download

    print(f"downloading {repo_id}...")
    snapshot_download(
        repo_id,
        cache_dir=str(CACHE),
        local_dir_use_symlinks=True,
        allow_patterns=allow_patterns,
    )
    print(f"  done: {repo_id}")


def download_surya_gguf() -> None:
    download_hf(
        "datalab-to/surya-ocr-2-gguf",
        allow_patterns=["*.gguf"],
    )


def download_chandra() -> None:
    download_hf("datalab-to/chandra-ocr-2")


def download_trocr() -> None:
    download_hf("microsoft/trocr-large-handwritten")


def download_surya_detector() -> None:
    # surya downloads detection + error models from datalab s3 on first use;
    # trigger via python import when surya is installed.
    surya_root = ROOT / "third_party" / "surya"
    if not surya_root.exists():
        print("surya source missing, skipping detector warmup")
        return
    sys.path.insert(0, str(surya_root))
    os.environ.setdefault("SURYA_INFERENCE_BACKEND", "llamacpp")
    try:
        from surya.inference import SuryaInferenceManager

        print("warming surya inference manager (downloads gguf if needed)...")
        SuryaInferenceManager()
        print("  surya inference ready")
    except Exception as exc:
        print(f"  surya warmup deferred: {exc}")


def _ensure_ssl_certificates() -> None:
    try:
        import certifi
        import os

        os.environ.setdefault("SSL_CERT_FILE", certifi.where())
        os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())
    except Exception:
        pass


def download_easyocr() -> None:
    if not _pip_importable("easyocr"):
        print("easyocr not installed yet, skipping")
        return
    _ensure_ssl_certificates()
    import easyocr

    langs = ["en", "fr", "es", "de", "it", "pt"]
    print(f"downloading easyocr models for {langs}...")
    try:
        easyocr.Reader(langs, gpu=False, verbose=True)
        print("  easyocr ready")
    except Exception as exc:
        print(f"  easyocr download deferred: {exc}")


def ensure_llama_server() -> None:
    if subprocess.run(["which", "llama-server"], capture_output=True).returncode == 0:
        print("llama-server found")
        return
    print("llama-server not found — install with: brew install llama.cpp")


def main() -> int:
    _ensure_ssl_certificates()
    print("marginalia ocr model download")
    print(f"cache: {CACHE}")
    ensure_llama_server()
    download_surya_gguf()
    download_chandra()
    download_trocr()
    download_easyocr()
    download_surya_detector()
    print("all model downloads complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
