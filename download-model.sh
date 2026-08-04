#!/usr/bin/env bash
# Download the DeepSeek V4 Flash GGUF into ~/models/gguf using a throw-away
# container (nothing is installed on the host). Resumable — safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

# --- configuration ---------------------------------------------------------
REPOSITORY="unsloth/DeepSeek-V4-Flash-0731-GGUF"
QUANT="UD-IQ3_XXS"                       # 104 GB, 4 shards. Fallback: UD-IQ2_M (90.9 GB)
DESTINATION="/home/joran/models/gguf"    # NOT the HF cache — see CLAUDE.md
REQUIRED_FREE_GB=120
MAX_WORKERS=8
# ---------------------------------------------------------------------------

mkdir -p "$DESTINATION"

avail_gb=$(df -BG --output=avail "$DESTINATION" | tail -1 | tr -dc '0-9')
if [ "$avail_gb" -lt "$REQUIRED_FREE_GB" ]; then
  echo "need ${REQUIRED_FREE_GB}G free at $DESTINATION, have ${avail_gb}G" >&2
  exit 1
fi
echo "downloading $REPOSITORY [$QUANT] -> $DESTINATION (${avail_gb}G free)"

# --user keeps the downloaded files owned by us, not root.
# HF_HOME is parked on the same big filesystem so the xet chunk cache can't fill /.
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e HF_HOME=/out/.hfcache \
  -v "$DESTINATION:/out" \
  python:3.12-slim \
  sh -c "pip install --quiet --user huggingface_hub && \
         /tmp/.local/bin/hf download '$REPOSITORY' \
           --include '${QUANT}/*' \
           --local-dir /out \
           --max-workers $MAX_WORKERS"

rm -rf "${DESTINATION:?}/.hfcache"
exec ./verify-model.sh
