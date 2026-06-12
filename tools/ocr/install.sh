#!/usr/bin/env bash
# Install local OCR models and Python environment for marginalia.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="$ROOT/tools/ocr/.venv"
CACHE="$HOME/.cache/datalab/models"

echo "== marginalia ocr install =="
echo "repo: $ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required"
  exit 1
fi

# llama-server is required for surya on apple silicon / cpu
if ! command -v llama-server >/dev/null 2>&1; then
  echo "installing llama.cpp (provides llama-server)..."
  if command -v brew >/dev/null 2>&1; then
    brew install llama.cpp
  else
    echo "warning: brew not found. install llama-server manually for surya ocr."
  fi
fi

echo "creating python venv at $VENV..."
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip wheel setuptools

echo "installing surya from vendored source..."
pip install -e "$ROOT/third_party/surya"

echo "installing ensemble ocr dependencies..."
pip install -r "$ROOT/tools/ocr/requirements.txt"

# paddleocr is optional on macos (paddlepaddle wheels are limited)
if python -c "import paddle" 2>/dev/null; then
  echo "paddleocr available"
else
  echo "note: paddleocr skipped on this platform (easyocr covers multilingual)"
fi

mkdir -p "$CACHE"
export MODEL_CACHE_DIR="$CACHE"
export HF_HOME="$HOME/.cache/huggingface"
export PYTHONPATH="$ROOT"

echo "downloading model weights (this may take a while)..."
python "$ROOT/tools/ocr/download_models.py"

echo ""
echo "install complete."
echo ""
echo "start servers:"
echo "  $ROOT/tools/ocr/start_servers.sh"
echo ""
echo "configure the ios app (xcode scheme environment or shell):"
echo "  SURYA_OCR_ENDPOINT=http://127.0.0.1:8765/ocr"
echo "  CHANDRA_OCR_ENDPOINT=http://127.0.0.1:8766/ocr"
echo "  VISION_LANGUAGE_OCR_ENDPOINT=http://127.0.0.1:8767/"
echo "  VISION_LANGUAGE_OCR_MODEL=marginalia-ocr-ensemble-v1"
