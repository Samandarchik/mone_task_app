#!/usr/bin/env bash
# Finder'da ikki marta bosing: pubspec.yaml dagi versiyani O'ZGARTIRMASDAN
# (aynan shu versiya va build raqami bilan) iOS'ni App Store/TestFlight'ga yuboradi.
# Versiyani oshirib yuborish kerak bo'lsa — deploy_ios.command ni ishlating.
cd "$(dirname "$0")" || exit 1
exec ./deploy_ios.command --no-bump
