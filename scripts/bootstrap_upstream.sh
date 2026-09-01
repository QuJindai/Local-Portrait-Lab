#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL="https://github.com/rmatif/Local-Diffusion.git"
UPSTREAM_COMMIT="184b7f92cf2f810e7d5eb4b04b190a5da829005f"
BUILD_ROOT="${PORTRAIT_BUILD_ROOT:-$ROOT_DIR/_build}"
UPSTREAM_DIR="$BUILD_ROOT/local-diffusion"

progress() {
  printf '[portrait-bootstrap] %s\n' "$*"
}

rm -rf "$UPSTREAM_DIR"
mkdir -p "$BUILD_ROOT"

progress "clone upstream"
git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$UPSTREAM_DIR"

progress "checkout locked commit $UPSTREAM_COMMIT"
git -C "$UPSTREAM_DIR" checkout --detach "$UPSTREAM_COMMIT"
actual="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [[ "$actual" != "$UPSTREAM_COMMIT" ]]; then
  printf 'ERROR: expected upstream %s, got %s\n' "$UPSTREAM_COMMIT" "$actual" >&2
  exit 21
fi

progress "apply portrait overlay"
if [[ -d "$ROOT_DIR/overlay/lib" ]]; then
  mkdir -p "$UPSTREAM_DIR/lib"
  cp -a "$ROOT_DIR/overlay/lib/." "$UPSTREAM_DIR/lib/"
fi
if [[ -d "$ROOT_DIR/overlay/test" ]]; then
  mkdir -p "$UPSTREAM_DIR/test"
  cp -a "$ROOT_DIR/overlay/test/." "$UPSTREAM_DIR/test/"
fi
if [[ -d "$ROOT_DIR/overlay/android" ]]; then
  mkdir -p "$UPSTREAM_DIR/android"
  cp -a "$ROOT_DIR/overlay/android/." "$UPSTREAM_DIR/android/"
fi

cat > "$BUILD_ROOT/UPSTREAM_LOCK.txt" <<EOF
url=$UPSTREAM_URL
commit=$UPSTREAM_COMMIT
actual=$actual
EOF

progress "ready: $UPSTREAM_DIR"
printf '%s\n' "$UPSTREAM_DIR"
