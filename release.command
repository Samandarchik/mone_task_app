#!/usr/bin/env bash
#
# Mone Task App — BIR BOSISHDA RELIZ (Finder'da ikki marta bosing).
# Versiyani oshiradi, pubspec.yaml ni commit qilib main ga push qiladi —
# qolganini GitHub o'zi qiladi (.github/workflows/release.yml):
#   Windows -> GitHub Releases (kompyuterlardagi ilovalar o'zi yangilanadi)
#   iOS     -> App Store Connect -> TestFlight
#
#   ./release.command            0.3.9 -> 0.3.10 (+310)
#   ./release.command --minor    0.3.9 -> 0.4.0  (+400)
#   ./release.command --major    0.3.9 -> 1.0.0  (+10000)
#   ./release.command --same     versiyani o'zgartirmay, joriysini qayta
#                                yig'ish (GitHub'da workflow'ni qo'lda ishga
#                                tushiradi)
#
# Build raqami versiyadan hisoblanadi (deploy_ios.command bilan bir xil):
#     build = major*10000 + minor*100 + patch
# Faqat pubspec.yaml commit qilinadi — boshqa fayllaringizga tegmaydi.
# Kerak: gh (GitHub CLI) tizimga kirgan bo'lishi (`gh auth status`).

set -euo pipefail
cd "$(dirname "$0")"

pause_if_interactive() {
    local code=$?
    if [ -t 0 ]; then
        echo
        [ $code -eq 0 ] || echo "[XATO] Skript $code kodi bilan tugadi."
        read -r -p "Yopish uchun Enter bosing..."
    fi
}
trap pause_if_interactive EXIT

BUMP=patch
case "${1:-}" in
    "") ;;
    --minor) BUMP=minor ;;
    --major) BUMP=major ;;
    --same)  BUMP=none ;;
    -h|--help) awk 'NR>2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "Noma'lum parametr: $1"; exit 1 ;;
esac

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "[XATO] main branchda emassiz ($BRANCH)."
    exit 1
fi
git pull --rebase --autostash origin main

CURRENT=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
SEMVER=${CURRENT%%+*}
IFS=. read -r MAJ MIN PAT <<<"$SEMVER"

if [ "$BUMP" = "none" ]; then
    echo "Versiya o'zgarmaydi: $CURRENT — GitHub'da relizni qayta ishga tushiraman"
    gh workflow run release.yml --ref main
    sleep 5
    echo
    echo "Kuzatish: $(gh run list --workflow release.yml -L 1 --json url -q '.[0].url')"
    exit 0
fi

case "$BUMP" in
    patch) PAT=$((PAT + 1)) ;;
    minor) MIN=$((MIN + 1)); PAT=0 ;;
    major) MAJ=$((MAJ + 1)); MIN=0; PAT=0 ;;
esac
NEW="$MAJ.$MIN.$PAT"
BUILD=$((MAJ * 10000 + MIN * 100 + PAT))

echo "============================================"
echo "  Reliz: $CURRENT  ->  $NEW+$BUILD"
echo "============================================"

sed -i '' "s/^version: .*/version: $NEW+$BUILD/" pubspec.yaml
git add pubspec.yaml
git commit -m "Versiya $NEW ($BUILD)"
git push origin main

sleep 8
echo
echo "TAYYOR. GitHub yig'yapti (Windows ~15 daq, iOS ~30 daq):"
echo "  $(gh run list --workflow release.yml -L 1 --json url -q '.[0].url' 2>/dev/null || echo 'https://github.com/Samandarchik/mone_task_app/actions')"
