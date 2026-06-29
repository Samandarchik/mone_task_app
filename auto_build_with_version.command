#!/bin/bash
# ============================================
#  task_app APK auto-build with version (macOS)
# ============================================

# Skript joylashgan papkaga o'tish
cd "$(dirname "$0")" || exit 1

APP_NAME="task_app"

# --- pubspec.yaml dan versiyani o'qish (version: 0.2.3+23 -> 0.2.3) ---
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version://; s/+.*//; s/ //g')

if [ -z "$VERSION" ]; then
  echo "[XATO] pubspec.yaml dan versiya topilmadi."
  exit 1
fi

echo "============================================"
echo "  Build: ${APP_NAME}_${VERSION}.apk"
echo "============================================"
echo

# --- APK build ---
flutter build apk --release || { echo "[XATO] Build muvaffaqiyatsiz tugadi."; exit 1; }

SRC="build/app/outputs/flutter-apk/app-release.apk"
DEST="build/app/outputs/flutter-apk/${APP_NAME}_${VERSION}.apk"

if [ ! -f "$SRC" ]; then
  echo "[XATO] APK topilmadi: $SRC"
  exit 1
fi

cp -f "$SRC" "$DEST"

echo
echo "============================================"
echo "  TAYYOR!"
echo "  Fayl: $DEST"
echo "============================================"

# --- APK papkasini Finder'da ochish ---
open build/app/outputs/flutter-apk

read -p "Yopish uchun Enter bosing..."
