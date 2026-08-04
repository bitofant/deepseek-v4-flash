#!/usr/bin/env bash
# Move the pinned llama.cpp submodule to a newer upstream release, then rebuild.
#   ./update.sh [<tag>]      default: latest release tag
#   ./update.sh <tag> --no-build
set -euo pipefail
cd "$(dirname "$0")"

SUBMODULE="llama.cpp"

[ -z "$(git -C "$SUBMODULE" status --porcelain)" ] || {
  echo "$SUBMODULE has local changes — refusing to update (patches belong in this repo, not upstream)" >&2
  exit 1
}

OLD=$(git -C "$SUBMODULE" describe --tags 2>/dev/null || echo unknown)
git -C "$SUBMODULE" fetch --tags origin

TAG="${1:-}"
if [ -z "$TAG" ] || [ "$TAG" = --no-build ]; then
  TAG=$(git -C "$SUBMODULE" tag -l 'b[0-9]*' --sort=-v:refname | head -1)
fi

git -C "$SUBMODULE" checkout -q "$TAG"
echo "llama.cpp: $OLD -> $(git -C "$SUBMODULE" describe --tags)"

for a in "$@"; do [ "$a" = --no-build ] && { echo "skipping build"; exit 0; }; done
exec ./build-async.sh start
