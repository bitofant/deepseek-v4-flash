#!/usr/bin/env bash
# Check the GGUF shards are all present and self-consistent.
set -euo pipefail
cd "$(dirname "$0")"

QUANT="${QUANT:-UD-IQ3_XXS}"
DESTINATION="${DESTINATION:-/home/joran/models/gguf}"
DIR="$DESTINATION/$QUANT"

[ -d "$DIR" ] || { echo "missing $DIR — run ./download-model.sh" >&2; exit 1; }

shopt -s nullglob
shards=("$DIR"/*.gguf)
(( ${#shards[@]} )) || { echo "no .gguf in $DIR — run ./download-model.sh" >&2; exit 1; }

# Shard names end in -0000N-of-0000M.gguf; M must match what we actually have.
expected=$(basename "${shards[0]}" | sed -nE 's/.*-of-0*([0-9]+)\.gguf/\1/p')
if [ -n "$expected" ] && [ "$expected" != "${#shards[@]}" ]; then
  echo "incomplete: found ${#shards[@]} shard(s), manifest says $expected — re-run ./download-model.sh" >&2
  exit 1
fi

# A truncated download leaves a short final shard; llama.cpp only fails minutes in.
for f in "${shards[@]}"; do
  [ -s "$f" ] || { echo "empty shard: $f" >&2; exit 1; }
  head -c4 "$f" | grep -qa GGUF || { echo "bad magic (not a GGUF): $f" >&2; exit 1; }
done

echo "OK  ${#shards[@]} shard(s), $(du -shc "${shards[@]}" | tail -1 | cut -f1) total"
echo "$DIR"
