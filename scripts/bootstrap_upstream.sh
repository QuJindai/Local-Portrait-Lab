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

progress "declare Portrait Lab checksum/archive dependencies"
python3 - "$UPSTREAM_DIR/pubspec.yaml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text(encoding='utf-8')
needle = '  path_provider: ^2.1.5\n'
if needle not in text:
    raise SystemExit('path_provider dependency anchor missing')
extra = ''
if '\n  crypto:' not in text:
    extra += '  crypto: ^3.0.6\n'
if '\n  archive:' not in text:
    extra += '  archive: ^4.0.2\n'
if extra:
    text = text.replace(needle, needle + extra, 1)
p.write_text(text, encoding='utf-8')
PY

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
