#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?usage: verify_portrait_android.sh <materialized-app-dir>}"
GRADLE="$APP_DIR/android/app/build.gradle"
MANIFEST="$APP_DIR/android/app/src/main/AndroidManifest.xml"
ACTIVITY="$APP_DIR/android/app/src/main/kotlin/com/qujindai/localportraitlab/MainActivity.kt"

fail() {
  printf 'PORTRAIT_ANDROID_FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'namespace "com.qujindai.localportraitlab"' "$GRADLE" || fail 'namespace is not com.qujindai.localportraitlab'
grep -Fq 'applicationId "com.qujindai.localportraitlab"' "$GRADLE" || fail 'applicationId is not com.qujindai.localportraitlab'
grep -Fq 'android:label="Portrait Lab"' "$MANIFEST" || fail 'application label is not Portrait Lab'
grep -Fq 'android:name="com.qujindai.localportraitlab.MainActivity"' "$MANIFEST" || fail 'Portrait Lab MainActivity is not wired'
grep -Fq 'android.permission.INTERNET' "$MANIFEST" || fail 'INTERNET permission is required for in-app model downloads'
[[ -f "$ACTIVITY" ]] || fail 'Portrait Lab MainActivity source is missing'

grep -R -Fq 'MANAGE_EXTERNAL_STORAGE' "$APP_DIR/android/app/src/main" && fail 'MANAGE_EXTERNAL_STORAGE is forbidden'
grep -R -Fq 'READ_EXTERNAL_STORAGE' "$APP_DIR/android/app/src/main" && fail 'READ_EXTERNAL_STORAGE is forbidden'
grep -R -Fq 'WRITE_EXTERNAL_STORAGE' "$APP_DIR/android/app/src/main" && fail 'WRITE_EXTERNAL_STORAGE is forbidden'

printf 'PORTRAIT_ANDROID_PASS package=com.qujindai.localportraitlab label=Portrait Lab broad_storage=none internet=enabled\n'
