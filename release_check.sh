#!/usr/bin/env bash
#
# Reliz oldidan majburiy tekshiruv. Biror qadam yiqilsa — reliz to'xtaydi.
#   1. flutter analyze  — kodda xato (error) bo'lmasligi kerak
#   2. flutter test     — ilova testlari
#   3. go vet + go test — server (backend/) testlari
#
# auto_build_with_version.command va deploy_ios.command uni o'zi chaqiradi.
# Qo'lda: ./release_check.sh
# Shoshilinch holatda o'tkazib yuborish: SKIP_RELEASE_CHECK=1 ./deploy_ios.command
set -euo pipefail
cd "$(dirname "$0")"

if [ "${SKIP_RELEASE_CHECK:-0}" = "1" ]; then
    echo "⚠️  Reliz tekshiruvi o'tkazib yuborildi (SKIP_RELEASE_CHECK=1)"
    exit 0
fi

step() { echo; echo "── $1"; }

step "flutter analyze (faqat xatolar to'xtatadi)"
flutter analyze --no-fatal-warnings --no-fatal-infos lib test

step "flutter test"
flutter test

if command -v go >/dev/null 2>&1; then
    step "backend: go vet + go test"
    (cd backend && go vet ./... && go test ./...)
else
    echo "⚠️  go o'rnatilmagan — backend testlari o'tkazib yuborildi"
fi

echo
echo "✅ Reliz tekshiruvi o'tdi"
