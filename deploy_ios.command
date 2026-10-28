#!/usr/bin/env bash
#
# Mone Task App (uz.uzaidev.taskapp) — iOS build, App Store Connect'ga yuklash va
# TestFlight'ga AVTOMAT tarqatish. Finder'da ikki marta bosib ham, terminaldan
# ham ishlatsa bo'ladi.
#
#   ./deploy_ios.command                  versiyani oshiradi (0.3.9 -> 0.3.10)
#   ./deploy_ios.command --minor          o'rta raqam  (0.3.9 -> 0.4.0)
#   ./deploy_ios.command --major          bosh raqam   (0.3.9 -> 1.0.0)
#   ./deploy_ios.command --version 0.4.0  versiyani qo'lda belgilash
#   ./deploy_ios.command --build          versiyani o'zgartirmay faqat build +1
#                                         (App Store shu build'ni allaqachon olgan bo'lsa)
#   ./deploy_ios.command --no-bump        hech nimaga tegmaydi (aynan shu build'ni qayta yuklash)
#   ./deploy_ios.command --no-git         pubspec versiyasini commit/push qilmaydi
#   ./deploy_ios.command --groups "A,B"   faqat shu TestFlight guruhlariga
#   ./deploy_ios.command --notes "matn"   "What to Test" izohi
#   ./deploy_ios.command --no-wait        yuklab qo'yadi, TestFlight tarqatishni kutmaydi
#   ./deploy_ios.command --validate       yuklamaydi, faqat App Store tekshiruvidan o'tkazadi
#   ./deploy_ios.command --clean          Xcode keshini tozalab build qiladi
#   ./deploy_ios.command --analyze        build'dan oldin `flutter analyze lib` ishlatadi
#
# Yuklangandan keyin (parametrsiz) skript o'zi:
#   1. build "PROCESSING" dan "VALID" ga o'tguncha kutadi (odatda 5-15 daqiqa)
#   2. export compliance (shifrlash) javobini qo'yadi — bo'lmasa TestFlight
#      "Missing Compliance" deb turib qoladi
#   3. "What to Test" izohini yozadi
#   4. build'ni TestFlight guruhlariga qo'shadi -> testerlarga xabar O'ZI boradi
#      (tashqi/external guruh bo'lsa beta review'ga ham o'zi yuboradi)
#   5. pubspec.yaml dagi versiya o'zgarishini commit qilib, origin'ga push qiladi
#      (faqat pubspec.yaml — boshqa fayllaringizga tegmaydi; --no-git bilan o'chadi)
#
# BUILD RAQAMI QO'LDA YOZILMAYDI. U shunchaki o'suvchi hisoblagich:
#     yangi build = max(pubspec'dagi +N, App Store Connect'dagi eng katta) + 1
# Shuning uchun pubspec boshqa kompyuterda qolib ketgan bo'lsa ham raqam
# pasaymaydi. Siz faqat versiya (X.Y.Z) haqida o'ylaysiz.
#
# `+N` ni butunlay olib tashlab bo'lmaydi: iOS'da Flutter uni versiyaning
# o'zidan oladi (ishlaydi), lekin Android'da versionCode `1` ga tushib qoladi —
# eski ilova ustiga o'rnatilmaydi (INSTALL_FAILED_VERSION_DOWNGRADE) va Play
# Store rad etadi.
#
# ⚠️ Windows relizi bilan bog'liq: bu skript pubspec.yaml dagi `version:` ni
# o'zgartiradi. build_windows.bat -> publish_release.ps1 ham shu versiyani
# o'qiydi, ya'ni iOS deploy'dan keyin Windows relizi keyingi raqamdan boshlanadi.
# Bu normal (Windows faqat X.Y.Z qismini oladi, `+N` ga qaramaydi).
#
# Konfiguratsiya: ~/.mone_appstore.env (bo'lmasa ~/.hr_appstore.env,
# ~/.sadinov_appstore.env yoki ~/.workly_appstore.env ishlatiladi — ilovalar bitta Apple jamoasida: KC2VPYBYF5):
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# Kalit fayl: ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8

set -euo pipefail

cd "$(dirname "$0")"

# Finder'dan (ikki bosish) ochilganda oynani natija bilan ochiq qoldirish
pause_if_interactive() {
    local code=$?
    rm -f "${ASC_PY:-}"
    if [ -t 0 ]; then
        echo
        [ $code -eq 0 ] || echo "[XATO] Skript $code kodi bilan tugadi."
        read -r -p "Yopish uchun Enter bosing..."
    fi
}
ASC_PY=""
trap pause_if_interactive EXIT

# Finder'dan ochilganda PATH faqat /usr/bin:/bin:/usr/sbin:/sbin bo'ladi — flutter u yerda yo'q.
# MUHIM: `zsh -lc` ~/.zshrc ni O'QIMAYDI (u faqat interaktiv shellda o'qiladi), `-i` kerak.
if ! command -v flutter >/dev/null 2>&1; then
    for d in "$HOME/developer/flutter/bin" "$HOME/development/flutter/bin" \
             "$HOME/flutter/bin" /opt/homebrew/bin /usr/local/bin; do
        [ -x "$d/flutter" ] && PATH="$d:$PATH" && break
    done
fi
if ! command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(/bin/zsh -ilc 'command -v flutter' 2>/dev/null | tail -1 || true)"
    if [ -n "$FLUTTER_BIN" ] && [ -x "$FLUTTER_BIN" ]; then
        PATH="$(dirname "$FLUTTER_BIN"):$PATH"
    fi
fi
command -v flutter >/dev/null 2>&1 || { echo "flutter topilmadi (PATH)." >&2; exit 1; }

BUMP=patch          # patch | minor | major | build | none
VALIDATE=0
CLEAN=0
NO_WAIT=0
ANALYZE=0
GIT_PUSH=1
NEW_VERSION=""
# DIQQAT: `GROUPS` nomini ishlatib bo'lmaydi — u bash'ning maxsus o'zgaruvchisi
# (foydalanuvchi guruh ID lari), unga yozib bo'lmaydi va "$GROUPS" -> 20 bo'lib ketadi.
TF_GROUPS=""
NOTES="${ASC_NOTES:-}"
WAIT_MIN="${ASC_WAIT_MIN:-30}"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-bump)          BUMP=none ;;
        --build|--build-only) BUMP=build ;;
        --patch)            BUMP=patch ;;
        --minor)            BUMP=minor ;;
        --major)            BUMP=major ;;
        --no-git)   GIT_PUSH=0 ;;
        --no-wait)  NO_WAIT=1 ;;
        --validate) VALIDATE=1 ;;
        --clean)    CLEAN=1 ;;
        --analyze)  ANALYZE=1 ;;
        --version)  NEW_VERSION="${2:-}"; shift ;;
        --groups)   TF_GROUPS="${2:-}"; shift ;;
        --notes)    NOTES="${2:-}"; shift ;;
        -h|--help)  awk 'NR>2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *)          echo "Noma'lum parametr: $1"; exit 1 ;;
    esac
    shift
done

# --- 1. Konfiguratsiya ---

CONFIG="${ASC_CONFIG:-}"
if [ -z "$CONFIG" ]; then
    for c in "$HOME/.mone_appstore.env" "$HOME/.hr_appstore.env" "$HOME/.sadinov_appstore.env" "$HOME/.workly_appstore.env"; do
        [ -f "$c" ] && CONFIG="$c" && break
    done
fi
# Konfiguratsiya yo'q, lekin terminal interaktiv bo'lsa — bir martalik sozlash:
# Key ID / Issuer ID so'raladi, .p8 fayl kerakli joyga nusxalanadi.
if { [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; } && [ -t 0 ]; then
    echo "App Store Connect API kaliti hali sozlanmagan — bir martalik sozlash."
    echo "(App Store Connect -> Users and Access -> Integrations -> App Store Connect API)"
    echo
    read -r -p "Key ID (10 belgi, masalan 2X9R4HXF34): " IN_KEY_ID
    read -r -p "Issuer ID (xxxxxxxx-xxxx-...): " IN_ISSUER_ID
    IN_KEY_ID="$(echo "$IN_KEY_ID" | tr -d '[:space:]')"
    IN_ISSUER_ID="$(echo "$IN_ISSUER_ID" | tr -d '[:space:]')"
    [[ "$IN_KEY_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Key ID noto'g'ri: $IN_KEY_ID" >&2; exit 1; }
    [[ "$IN_ISSUER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "Issuer ID noto'g'ri: $IN_ISSUER_ID" >&2; exit 1; }

    DEST_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${IN_KEY_ID}.p8"
    if [ ! -f "$DEST_KEY" ]; then
        DEFAULT_P8="$HOME/Downloads/AuthKey_${IN_KEY_ID}.p8"
        [ -f "$DEFAULT_P8" ] || DEFAULT_P8=""
        read -r -p "AuthKey_${IN_KEY_ID}.p8 fayl yo'li (terminalga sudrab tashlang)${DEFAULT_P8:+ [$DEFAULT_P8]}: " IN_P8
        IN_P8="${IN_P8:-$DEFAULT_P8}"
        # Sudrab tashlanganda yo'l qo'shtirnoq yoki "\ " bilan keladi
        IN_P8="$(echo "$IN_P8" | sed "s/^[\"']//; s/[\"'] *$//; s/\\\\ / /g; s/ *$//")"
        [ -f "$IN_P8" ] || { echo "Fayl topilmadi: $IN_P8" >&2; exit 1; }
        mkdir -p "$(dirname "$DEST_KEY")"
        cp "$IN_P8" "$DEST_KEY"
        chmod 600 "$DEST_KEY"
    fi

    CONFIG="$HOME/.mone_appstore.env"
    printf 'ASC_KEY_ID=%s\nASC_ISSUER_ID=%s\n' "$IN_KEY_ID" "$IN_ISSUER_ID" > "$CONFIG"
    chmod 600 "$CONFIG"
    echo "Saqlandi: $CONFIG va $DEST_KEY"
    echo
fi
if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
    cat >&2 <<EOF
Konfiguratsiya topilmadi.

Quyidagicha yarating:
    cat > $HOME/.mone_appstore.env <<'CONF'
    ASC_KEY_ID=XXXXXXXXXX
    ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    CONF
    chmod 600 $HOME/.mone_appstore.env

Key ID va Issuer ID: App Store Connect -> Users and Access -> Integrations
-> App Store Connect API sahifasida.
EOF
    exit 1
fi
echo "Konfiguratsiya: $CONFIG"

# shellcheck disable=SC1090
source "$CONFIG"

: "${ASC_KEY_ID:?$CONFIG ichida ASC_KEY_ID yo'q}"
: "${ASC_ISSUER_ID:?$CONFIG ichida ASC_ISSUER_ID yo'q}"

KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [ ! -f "$KEY_FILE" ]; then
    echo "Kalit fayl topilmadi: $KEY_FILE" >&2
    echo "AuthKey_${ASC_KEY_ID}.p8 faylini o'sha joyga nusxalang." >&2
    exit 1
fi

# Kerakli kutubxonasi (cryptography) BOR python3 ni topamiz. Finder'dan ochilganda
# `python3` = Apple'niki bo'lib qoladi, unda kutubxona yo'q.
PY_BIN=""
for cand in "${ASC_PYTHON:-}" python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -n "$cand" ] || continue
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import cryptography" >/dev/null 2>&1; then
        PY_BIN="$cand"
        break
    fi
done
if [ -z "$PY_BIN" ]; then
    cand="$(/bin/zsh -ilc 'command -v python3' 2>/dev/null | tail -1 || true)"
    if [ -n "$cand" ] && "$cand" -c "import cryptography" >/dev/null 2>&1; then
        PY_BIN="$cand"
    fi
fi
if [ -z "$PY_BIN" ]; then
    echo "cryptography kutubxonasi bor python3 topilmadi. O'rnating:" >&2
    echo "    python3 -m pip install cryptography" >&2
    exit 1
fi

BUNDLE_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);.*/\1/p' ios/Runner.xcodeproj/project.pbxproj \
    | grep -v RunnerTests | head -1)"
[ -n "$BUNDLE_ID" ] || { echo "PRODUCT_BUNDLE_IDENTIFIER topilmadi." >&2; exit 1; }
echo "Ilova: $BUNDLE_ID"

# --- 1b. App Store Connect yordamchisi ---
# Eslatma: bash 3.2 `$( ... <<HEREDOC ... )` ichidagi apostroflarni noto'g'ri o'qiydi,
# shuning uchun python alohida vaqtinchalik faylga yoziladi (trap uni o'chiradi).

ASC_PY="$(mktemp -t mone_asc)"
cat > "$ASC_PY" <<'PY'
"""App Store Connect API yordamchisi: build raqamini bilish va TestFlight'ga tarqatish."""
import base64, json, os, ssl, sys, time, urllib.error, urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as asym_utils

BASE = "https://api.appstoreconnect.apple.com"
# python.org'dan o'rnatilgan python macOS sertifikatlarini ko'rmaydi
# (CERTIFICATE_VERIFY_FAILED) — certifi bo'lsa uning CA ro'yxatini olamiz.
try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CTX = None
KEY_FILE  = os.environ["ASC_KEY_FILE"]
KEY_ID    = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
BUNDLE_ID = os.environ["BUNDLE_ID"]

_tok = {"value": None, "exp": 0}


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def token():
    """ES256 JWT. PyJWT shart emas — cryptography bilan o'zimiz imzolaymiz."""
    now = int(time.time())
    if _tok["value"] and now < _tok["exp"] - 60:
        return _tok["value"]
    key = serialization.load_pem_private_key(open(KEY_FILE, "rb").read(), password=None)
    head = _b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    body = _b64(json.dumps({"iss": ISSUER_ID, "iat": now, "exp": now + 900,
                            "aud": "appstoreconnect-v1"}).encode())
    signing_input = head + b"." + body
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = asym_utils.decode_dss_signature(der)
    sig = _b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    _tok["value"] = (signing_input + b"." + sig).decode()
    _tok["exp"] = now + 900
    return _tok["value"]


def api(path, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers={
        "Authorization": "Bearer " + token(),
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60, context=SSL_CTX) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"App Store Connect xatosi {e.code} ({method} {path}):\n{detail[:600]}")


def app_id():
    data = api(f"/v1/apps?filter[bundleId]={BUNDLE_ID}&limit=1").get("data", [])
    if not data:
        raise SystemExit(f"App Store Connect'da {BUNDLE_ID} topilmadi (kalit huquqini tekshiring).")
    return data[0]["id"]


def max_build(app):
    """Eng katta build raqami (hamma versiyalar bo'yicha)."""
    codes = [0]
    for b in api(f"/v1/builds?filter[app]={app}&limit=200&sort=-uploadedDate").get("data", []):
        try:
            codes.append(int(b["attributes"]["version"]))
        except (TypeError, ValueError):
            pass
    return max(codes)


def find_build(app, version, build_number, timeout_min):
    """Build App Store Connect'da paydo bo'lib, PROCESSING dan chiqishini kutamiz."""
    deadline = time.time() + timeout_min * 60
    shown = None
    while True:
        found = api(f"/v1/builds?filter[app]={app}"
                    f"&filter[preReleaseVersion.version]={version}"
                    f"&filter[version]={build_number}&limit=1").get("data", [])
        if found:
            state = found[0]["attributes"]["processingState"]
            if state != shown:
                print(f"  build holati: {state}", flush=True)
                shown = state
            if state == "VALID":
                return found[0]
            if state in ("FAILED", "INVALID"):
                raise SystemExit(f"Build qayta ishlashda rad etildi: {state}. "
                                 "App Store Connect'dagi xabarni tekshiring.")
        elif shown is None:
            print("  build hali ko'rinmadi, kutilmoqda...", flush=True)
            shown = "kutish"
        if time.time() > deadline:
            raise SystemExit(f"{timeout_min} daqiqada build tayyor bo'lmadi. "
                             "Keyinroq App Store Connect'dan qo'lda tarqatsangiz bo'ladi.")
        time.sleep(30)


def ensure_compliance(build):
    """Shifrlash (export compliance) javobi bo'lmasa TestFlight build'ni tarqatmaydi."""
    if build["attributes"].get("usesNonExemptEncryption") is None:
        print("  export compliance javobi qo'yilmoqda (shifrlash: yo'q)...", flush=True)
        api(f"/v1/builds/{build['id']}", "PATCH", {"data": {
            "type": "builds", "id": build["id"],
            "attributes": {"usesNonExemptEncryption": False},
        }})


def set_notes(build, notes):
    if not notes:
        return
    locs = api(f"/v1/builds/{build['id']}/betaBuildLocalizations?limit=50").get("data", [])
    if locs:
        for loc in locs:
            api(f"/v1/betaBuildLocalizations/{loc['id']}", "PATCH", {"data": {
                "type": "betaBuildLocalizations", "id": loc["id"],
                "attributes": {"whatsNew": notes},
            }})
    else:
        # Til ilovaning asosiy tili bo'lsin, aks holda API rad etadi
        app = api(f"/v1/apps/{app_id_cached}").get("data", {})
        locale = app.get("attributes", {}).get("primaryLocale") or "en-US"
        api("/v1/betaBuildLocalizations", "POST", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": locale, "whatsNew": notes},
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}},
        }})
    print("  'What to Test' izohi yozildi", flush=True)


def distribute(build, wanted):
    groups = api(f"/v1/apps/{app_id_cached}/betaGroups?limit=200").get("data", [])
    if wanted:
        names = [w.strip().lower() for w in wanted.split(",") if w.strip()]
        groups = [g for g in groups if g["attributes"]["name"].lower() in names]
        if not groups:
            raise SystemExit(f"Berilgan nom bo'yicha TestFlight guruhi topilmadi: {wanted}")
    if not groups:
        print("  [OGOHLANTIRISH] TestFlight guruhi yo'q — App Store Connect -> TestFlight ->")
        print("                  Groups da guruh yaratib, testerlarni qo'shing.", flush=True)
        return
    external = False
    for g in groups:
        attrs = g["attributes"]
        # "Avtomatik" ichki guruhlar (hasAccessToAllBuilds) HAR build'ni o'zi oladi;
        # ularga qo'lda qo'shishga API 422 qaytaradi ("Cannot add internal group").
        if attrs.get("isInternalGroup") and attrs.get("hasAccessToAllBuilds"):
            print(f"  {attrs['name']}: avtomatik ichki guruh — build o'zi tarqaladi",
                  flush=True)
            continue
        api(f"/v1/betaGroups/{g['id']}/relationships/builds", "POST",
            {"data": [{"type": "builds", "id": build["id"]}]})
        kind = "internal" if attrs.get("isInternalGroup") else "external"
        print(f"  guruhga qo'shildi: {attrs['name']} ({kind})", flush=True)
        external = external or not attrs.get("isInternalGroup")
    if external:
        # Tashqi testerlar uchun Apple beta review'i shart
        api("/v1/betaAppReviewSubmissions", "POST", {"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}},
        }})
        print("  tashqi guruh uchun beta review'ga yuborildi", flush=True)


cmd = sys.argv[1]
app_id_cached = app_id()

if cmd == "maxbuild":
    print(max_build(app_id_cached))
elif cmd == "distribute":
    version, build_number, notes, wait_min = sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
    groups = sys.argv[6] if len(sys.argv) > 6 else ""
    print("Build App Store Connect'da qayta ishlanishi kutilmoqda...", flush=True)
    b = find_build(app_id_cached, version, build_number, wait_min)
    ensure_compliance(b)
    set_notes(b, notes)
    distribute(b, groups)
else:
    raise SystemExit(f"Noma'lum buyruq: {cmd}")
PY

asc() {
    ASC_KEY_FILE="$KEY_FILE" ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" \
    BUNDLE_ID="$BUNDLE_ID" "$PY_BIN" "$ASC_PY" "$@"
}

# --- 2. Versiya ---

version_line() {
    grep '^version:' pubspec.yaml | head -1 | sed 's/^version: *//; s/[[:space:]]*#.*//; s/[[:space:]]*$//'
}

CURRENT="$(version_line)"
SEMVER="${CURRENT%%+*}"
case "$CURRENT" in
    *+*) OLD_BUILD="${CURRENT##*+}" ;;
    *)   OLD_BUILD=0 ;;   # pubspec'da +build yo'q ekan — 0 dan boshlaymiz
esac
[[ "$OLD_BUILD" =~ ^[0-9]+$ ]] || OLD_BUILD=0

# App Store Connect'dagi eng katta build raqamini oldindan so'raymiz: shu bilan (a) huquq/auth
# xatosi uzoq build'dan OLDIN chiqadi, (b) raqam u yerdagidan past bo'lib qolmaydi (pubspec
# boshqa kompyuterda qolib ketgan bo'lsa ham).
echo "App Store Connect'dagi mavjud build raqami tekshirilmoqda..."
set +e
ASC_MAX="$(asc maxbuild)"
ASC_RC=$?
set -e
if [ "$ASC_RC" -ne 0 ]; then
    echo "$ASC_MAX" >&2
    exit 1
fi
echo "  App Store Connect'dagi eng katta build: $ASC_MAX"

# Yangi build raqami shundan ham, pubspec'dagidan ham yuqori bo'lishi kerak
FLOOR="$OLD_BUILD"
[ "$ASC_MAX" -gt "$FLOOR" ] && FLOOR="$ASC_MAX"

[[ "$SEMVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "pubspec.yaml versiyasi X.Y.Z ko'rinishida emas: $CURRENT" >&2
    echo "Qo'lda bering: ./deploy_ios.command --version 0.3.10" >&2
    exit 1
}

if [ -n "$NEW_VERSION" ]; then
    [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "--version X.Y.Z ko'rinishida bo'lishi kerak: $NEW_VERSION" >&2
        exit 1
    }
    SEMVER="$NEW_VERSION"
fi

IFS=. read -r MAJ MIN PAT <<<"$SEMVER"

if [ -z "$NEW_VERSION" ]; then
    case "$BUMP" in
        patch) PAT=$((PAT + 1)) ;;
        minor) MIN=$((MIN + 1)); PAT=0 ;;
        major) MAJ=$((MAJ + 1)); MIN=0; PAT=0 ;;
        build|none) : ;;
    esac
fi

SEMVER="$MAJ.$MIN.$PAT"

case "$BUMP" in
    none)
        # Hech nimaga tegmaymiz — aynan pubspec'dagi qiymat bilan qayta yuklash
        # (odatda --validate bilan birga ishlatiladi).
        [ -n "$NEW_VERSION" ] || SEMVER="${CURRENT%%+*}"
        BUILD_NUM="$OLD_BUILD"
        ;;
    *)
        # versionCode faqat o'sishi mumkin (Android talabi + App Store ham
        # bir xil raqamni ikkinchi marta qabul qilmaydi).
        BUILD_NUM=$((FLOOR + 1))
        ;;
esac

TARGET="${SEMVER}+${BUILD_NUM}"
if [ "$TARGET" != "$CURRENT" ]; then
    # macOS sed — .bak faylsiz o'zgartirish
    sed -i '' "s/^version: .*/version: ${TARGET}/" pubspec.yaml
    echo "Versiya: $CURRENT -> $TARGET"
else
    echo "Versiya: $TARGET (o'zgarmadi)"
fi

# --- 3. Build ---

if [ "$ANALYZE" -eq 1 ]; then
    echo "flutter analyze lib ..."
    flutter analyze lib
fi

if [ "$CLEAN" -eq 1 ]; then
    echo "Xcode keshi tozalanmoqda..."
    # Faqat shu loyihaning DerivedData katalogi (boshqa loyihalarga tegilmaydi)
    xcodebuild -project ios/Runner.xcodeproj -showBuildSettings 2>/dev/null \
        | awk '/BUILD_DIR = /{print $3}' | head -1 \
        | sed 's#/Build/Products##' \
        | xargs rm -rf
    flutter clean >/dev/null
fi

echo "IPA build qilinmoqda..."
# flutter build ipa export bosqichida yiqilishi mumkin (Xcode'da hisob ulanmagan
# bo'lsa "No Accounts" / "No signing certificate iOS Distribution") — eski
# flutter bunda 0 bilan chiqardi, yangisi 1 bilan chiqadi. Ikkala holatda ham
# archive tayyor bo'lsa, pastdagi ASC API kalitli fallback export qiladi, shuning
# uchun set -e ni shu buyruq uchun o'chirib turamiz.
BUILD_STAMP="$(mktemp -t mone_buildstamp)"
set +e
flutter build ipa --release
FLUTTER_RC=$?
set -e

ARCHIVE="build/ios/archive/Runner.xcarchive"
# DIQQAT: `|| true`siz IPA yo'q bo'lganda pipefail+set -e skriptni SHU YERDA
# indamay o'ldiradi (ls bo'sh glob'da xato qaytaradi).
IPA="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)"

# flutter yiqilgan bo'lsa, archive AYNAN SHU ishga tushirishda yangilanganini
# tekshiramiz — eski archive'ni export qilib yubormaslik uchun.
if [ "$FLUTTER_RC" -ne 0 ] && [ ! "$ARCHIVE/Info.plist" -nt "$BUILD_STAMP" ]; then
    rm -f "$BUILD_STAMP"
    echo "Archive yaratilmadi — flutter build $FLUTTER_RC kodi bilan yiqildi." >&2
    exit "$FLUTTER_RC"
fi
rm -f "$BUILD_STAMP"

# flutter export IPA yaratmagan (yoki eski IPA qolib ketgan) bo'lsa — ASC API
# kaliti bilan qayta export qilamiz (cloud signing, Xcode hisobisiz ham ishlaydi).
if [ -z "$IPA" ] || [ "$ARCHIVE" -nt "$IPA" ]; then
    echo "flutter export IPA yaratmadi — API kalit bilan export qilinmoqda..."
    TEAM_ID="$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]\{10\}\);.*/\1/p' ios/Runner.xcodeproj/project.pbxproj | head -1)"
    PLIST="build/ios/ExportOptionsASC.plist"
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST_EOF
    rm -rf build/ios/ipa
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportPath build/ios/ipa \
        -exportOptionsPlist "$PLIST" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_FILE" \
        -authenticationKeyID "$ASC_KEY_ID" \
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    IPA="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)"
fi

[ -n "$IPA" ] || { echo "IPA fayl topilmadi — build muvaffaqiyatsiz." >&2; exit 1; }
echo "IPA tayyor: $IPA ($(du -h "$IPA" | cut -f1))"

# --- 4. App Store Connect ---

ACTION="--upload-app"
[ "$VALIDATE" -eq 1 ] && ACTION="--validate-app"

echo "App Store Connect'ga yuborilmoqda (${ACTION#--})..."
xcrun altool $ACTION \
    --type ios \
    --file "$IPA" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

if [ "$VALIDATE" -eq 1 ]; then
    echo "Tekshiruvdan o'tdi (yuklanmadi)."
    exit 0
fi
echo "Yuklandi: $TARGET"

# --- 5. Versiyani git'ga yozib qo'yish ---
# Faqat pubspec.yaml commit qilinadi — ish jarayonidagi boshqa fayllaringiz
# tegilmaydi. Push muvaffaqiyatsiz bo'lsa (masalan remote oldinda) — reliz
# baribir yuklangan, shuning uchun skript to'xtamaydi, ogohlantirish beradi.

if [ "$GIT_PUSH" -eq 1 ] && [ "$TARGET" != "$CURRENT" ] \
   && command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    echo "pubspec.yaml commit qilinmoqda ($BRANCH)..."
    if git commit -q -m "mone_task_app: versiya $TARGET (iOS reliz)" -- pubspec.yaml; then
        if git push -q origin "$BRANCH"; then
            echo "  push qilindi: origin/$BRANCH"
        else
            echo "  [OGOHLANTIRISH] push o'tmadi — qo'lda: git pull --rebase && git push"
        fi
    else
        echo "  [OGOHLANTIRISH] commit qilinmadi (o'zgarish yo'q yoki git rad etdi)."
    fi
fi

# --- 6. TestFlight ---

if [ "$NO_WAIT" -eq 1 ]; then
    echo "TestFlight tarqatish kutilmadi (--no-wait) — build App Store Connect'da 5-15"
    echo "daqiqada tayyor bo'ladi, keyin guruhga qo'lda qo'shasiz."
    exit 0
fi

asc distribute "$SEMVER" "$BUILD_NUM" "$NOTES" "$WAIT_MIN" "$TF_GROUPS"

echo
echo "Tayyor — $TARGET TestFlight'da testerlarga tarqatildi."
