#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL="https://github.com/rmatif/Local-Diffusion.git"
UPSTREAM_COMMIT="184b7f92cf2f810e7d5eb4b04b190a5da829005f"
IDENTITY_SOURCE_URL="https://github.com/Parasaran-Python/android-face-fusion.git"
IDENTITY_SOURCE_COMMIT="f38a70e4bacaab4132538421c471f9d4d3ccac00"
BUILD_ROOT="${PORTRAIT_BUILD_ROOT:-$ROOT_DIR/_build}"
UPSTREAM_DIR="$BUILD_ROOT/local-diffusion"
IDENTITY_SOURCE_DIR="$BUILD_ROOT/android-face-fusion-source"

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

progress "vendor pinned MIT Android face identity source"
rm -rf "$IDENTITY_SOURCE_DIR"
git clone --filter=blob:none --no-checkout "$IDENTITY_SOURCE_URL" "$IDENTITY_SOURCE_DIR"
git -C "$IDENTITY_SOURCE_DIR" checkout --detach "$IDENTITY_SOURCE_COMMIT"
identity_actual="$(git -C "$IDENTITY_SOURCE_DIR" rev-parse HEAD)"
if [[ "$identity_actual" != "$IDENTITY_SOURCE_COMMIT" ]]; then
  printf 'ERROR: expected identity source %s, got %s\n' "$IDENTITY_SOURCE_COMMIT" "$identity_actual" >&2
  exit 22
fi
IDENTITY_JAVA_SRC="$IDENTITY_SOURCE_DIR/app/src/main/java/com/pv/androidfacefusion"
IDENTITY_JAVA_DST="$UPSTREAM_DIR/android/app/src/main/java/com/pv/androidfacefusion"
mkdir -p "$IDENTITY_JAVA_DST"
for name in FaceDetector.java FaceEmbedder.java FaceSwapper.java ImageUtils.java OrtSessionHelper.java ModelDownloader.java; do
  test -s "$IDENTITY_JAVA_SRC/$name"
  cp "$IDENTITY_JAVA_SRC/$name" "$IDENTITY_JAVA_DST/$name"
done

# The upstream MIT sample embeds emap.bin as an asset. Portrait Lab deliberately
# keeps all identity weights/data out of the APK, so load the verified runtime
# copy from app-private filesDir instead.
python3 - "$IDENTITY_JAVA_DST/FaceSwapper.java" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
old = 'try (InputStream fis = context.getAssets().open("emap.bin")) {'
new = 'try (InputStream fis = new java.io.FileInputStream(new File(context.getFilesDir(), "emap.bin"))) {'
if old not in s:
    raise SystemExit('FaceSwapper EMAP asset anchor missing')
s = s.replace(old, new, 1)
s = s.replace('Loading EMAP from assets...', 'Loading verified EMAP from app-private storage...', 1)
s = s.replace('loaded successfully from assets', 'loaded successfully from app-private storage', 1)
p.write_text(s, encoding='utf-8')
PY

grep -F 'new java.io.FileInputStream(new File(context.getFilesDir(), "emap.bin"))' "$IDENTITY_JAVA_DST/FaceSwapper.java"

cat > "$BUILD_ROOT/UPSTREAM_LOCK.txt" <<EOF
url=$UPSTREAM_URL
commit=$UPSTREAM_COMMIT
actual=$actual
identity_source_url=$IDENTITY_SOURCE_URL
identity_source_commit=$IDENTITY_SOURCE_COMMIT
identity_source_actual=$identity_actual
EOF

progress "ready: $UPSTREAM_DIR"
printf '%s\n' "$UPSTREAM_DIR"
