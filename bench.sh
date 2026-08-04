#!/usr/bin/env bash
# Measure single-request prefill + decode against whatever serves :8000.
# Each run prepends a UUID so the server's prompt cache can't skew prefill.
set -euo pipefail
cd "$(dirname "$0")"

# --- configuration ---------------------------------------------------------
ENDPOINT="http://localhost:8000"
MODEL="DeepSeek-V4-Flash-0731"
PROMPT_TOKENS=(512 4096 16384)   # approximate prompt sizes to sweep
DECODE_TOKENS=150                # tokens to generate per run
GPU_SAMPLE=1                     # 1 = sample PCIe/SM counters during each run
# ---------------------------------------------------------------------------

C='\033[96m'; G='\033[92m'; RS='\033[0m'

# ~1 token per repetition of "token " for a rough, reproducible filler.
filler() { python3 -c "
import sys,random
random.seed(int(sys.argv[1]))
w=['alpha','beta','gamma','delta','epsilon','zeta','eta','theta']
print(' '.join(random.choice(w) for _ in range(int(sys.argv[1]))))
" "$1"; }

run() {
  local n=$1 tag=$2 gpucsv=""
  local prompt; prompt=$(filler "$n")
  local body; body=$(python3 -c "
import json,sys,uuid
p=sys.stdin.read()
print(json.dumps({
 'model':'$MODEL',
 'messages':[{'role':'user','content':str(uuid.uuid4())+' '+p+'\nCount slowly.'}],
 'max_tokens':$DECODE_TOKENS,'stream':False,'cache_prompt':False}))
" <<<"$prompt")

  local mon=""
  if [ "$GPU_SAMPLE" = 1 ]; then
    gpucsv=$(mktemp); nvidia-smi dmon -s put -d 1 -c 600 >"$gpucsv" 2>/dev/null & mon=$!
  fi

  local resp; resp=$(curl -s "$ENDPOINT/v1/chat/completions" -H 'Content-Type: application/json' -d "$body")

  [ -n "$mon" ] && { kill "$mon" 2>/dev/null || true; wait "$mon" 2>/dev/null || true; }

  echo "$resp" | jq -r --arg tag "$tag" '
    .timings as $t |
    "\($tag)\tprompt=\($t.prompt_n)\tprefill=\($t.prompt_per_second|floor) tok/s\tdecode=\($t.predicted_per_second|round) tok/s"' \
    || { echo "$resp" | head -c 400; return 1; }

  if [ -n "$gpucsv" ]; then
    # dmon -s put columns: 1=gpu 2=pwr 3=gtemp 4=mtemp 5=sm 6=mem ... 11=rxpci 12=txpci
    awk 'NR>2 && $11 ~ /^[0-9]+$/ {sm+=$5; rx+=$11; tx+=$12; pw+=$2; n++}
         END{if(n)printf "        avg sm=%.0f%%  pwr=%.0fW  pcie rx=%.0f MB/s  tx=%.0f MB/s  (n=%d)\n", sm/n, pw/n, rx/n, tx/n, n}' "$gpucsv"
    rm -f "$gpucsv"
  fi
}

echo -e "${C}==>${RS} warmup"
run 256 warmup >/dev/null 2>&1 || true

for n in "${PROMPT_TOKENS[@]}"; do
  echo -e "${C}==>${RS} prompt ~${n} tokens"
  run "$n" "  n=${n}"
done
echo -e "${G}done${RS}"
