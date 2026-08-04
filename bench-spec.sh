#!/usr/bin/env bash
# Decode benchmark for speculative decoding: asks the model to echo a source file
# back with one small edit, which is the case ngram drafting is supposed to win.
# Compare decode tok/s against the same prompt with --spec-type none.
set -euo pipefail
cd "$(dirname "$0")"

# --- configuration ---------------------------------------------------------
ENDPOINT="http://localhost:8000"
MODEL="DeepSeek-V4-Flash-0731"
DECODE_TOKENS=400
SOURCE_FILE="llama.cpp/common/speculative.h"   # ~200 lines of C++ to echo back
# ---------------------------------------------------------------------------

src=$(head -c 6000 "$SOURCE_FILE")
body=$(python3 -c "
import json,sys,uuid
src=sys.stdin.read()
msg=('Reproduce the following C++ header verbatim, changing only the copyright '
     'year to 2027. Output the full file, no commentary.\n\n'+src)
print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':msg}],
 'max_tokens':$DECODE_TOKENS,'stream':False,'temperature':0.0}))
" <<<"$src")

curl -s "$ENDPOINT/v1/chat/completions" -H 'Content-Type: application/json' -d "$body" \
  | jq -r '.timings as $t | "prefill=\($t.prompt_per_second|floor) tok/s  decode=\($t.predicted_per_second|round) tok/s  n_decoded=\($t.predicted_n)"'

curl -s "$ENDPOINT/slots" | jq -r '.[0] | "speculative=\(.speculative)"' 2>/dev/null || true
