#!/usr/bin/env bash
# Start all local OCR servers for marginalia.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="$ROOT/tools/ocr/.venv"
PID_DIR="$ROOT/tools/ocr/.pids"
LOG_DIR="$ROOT/tools/ocr/.logs"

mkdir -p "$PID_DIR" "$LOG_DIR"

if [[ ! -d "$VENV" ]]; then
  echo "venv missing — run tools/ocr/install.sh first"
  exit 1
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"
export PYTHONPATH="$ROOT"
export MODEL_CACHE_DIR="${MODEL_CACHE_DIR:-$HOME/.cache/datalab/models}"
export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
export SURYA_INFERENCE_BACKEND="${SURYA_INFERENCE_BACKEND:-llamacpp}"
export SURYA_INFERENCE_KEEP_ALIVE="${SURYA_INFERENCE_KEEP_ALIVE:-1}"

start_server() {
  local name="$1"
  local module="$2"
  local port="$3"
  local pid_file="$PID_DIR/$name.pid"
  local log_file="$LOG_DIR/$name.log"

  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "$name already running (pid $(cat "$pid_file"))"
    return
  fi

  echo "starting $name on port $port..."
  nohup python -m "$module" >"$log_file" 2>&1 &
  echo $! >"$pid_file"
  sleep 1
  if kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "  $name pid $(cat "$pid_file") log: $log_file"
  else
    echo "  $name failed to start — see $log_file"
    tail -20 "$log_file" || true
  fi
}

start_server surya tools.ocr.servers.surya_server 8765
start_server chandra tools.ocr.servers.chandra_server 8766
start_server adjudicator tools.ocr.servers.vision_adjudicator_server 8767

echo ""
echo "ocr endpoints:"
echo "  surya:       http://127.0.0.1:8765/ocr"
echo "  chandra:     http://127.0.0.1:8766/ocr"
echo "  adjudicator: http://127.0.0.1:8767/"
echo ""
echo "health checks:"
echo "  curl http://127.0.0.1:8765/health"
echo "  curl http://127.0.0.1:8766/health"
echo "  curl http://127.0.0.1:8767/health"
