#!/bin/zsh
set -euo pipefail
umask 022

KORNUCOPIA_ROOT="${0:A:h:h}"
KORNUCOPIA_BUNDLE_ONLY=false
if [[ "${1:-}" == "--bundle-only" ]]; then
  KORNUCOPIA_BUNDLE_ONLY=true
  shift
fi
if [[ $# -gt 1 ]]; then
  print -u2 "Uso: scripts/test.sh [--bundle-only] [caminho-do-app]"
  exit 2
fi
KORNUCOPIA_APP="${1:-$KORNUCOPIA_ROOT/build/Kornucopia.app}"
KORNUCOPIA_EXECUTABLE="$KORNUCOPIA_APP/Contents/MacOS/Kornucopia"
KORNUCOPIA_PLIST="$KORNUCOPIA_APP/Contents/Info.plist"

fail() { print -u2 "FAIL: $1"; exit 1; }
if [[ ! -d "$KORNUCOPIA_APP" || -L "$KORNUCOPIA_APP" ]]; then
  fail "App ausente ou inválido. Execute scripts/build.sh primeiro."
fi
/usr/bin/plutil -lint "$KORNUCOPIA_PLIST" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$KORNUCOPIA_PLIST")" == "net.allanpscheidt.kornucopia" ]] || fail "Identificador do app incorreto."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$KORNUCOPIA_PLIST")" == "Kornucopia" ]] || fail "Executável incorreto."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$KORNUCOPIA_PLIST")" == "14.0" ]] || fail "Versão mínima do macOS incorreta."
[[ "$(/usr/bin/lipo -archs "$KORNUCOPIA_EXECUTABLE")" == "arm64" ]] || fail "O app deve conter apenas Apple Silicon arm64."
KORNUCOPIA_MINOS="$(/usr/bin/otool -l "$KORNUCOPIA_EXECUTABLE" | /usr/bin/awk '/cmd LC_BUILD_VERSION/{found=1} found && $1=="minos"{print $2; exit}')"
[[ "$KORNUCOPIA_MINOS" == "14.0" ]] || fail "Deployment target do binário incorreto."
[[ -x "$KORNUCOPIA_EXECUTABLE" ]] || fail "O executável não tem permissão de execução."
[[ "$(/usr/bin/find "$KORNUCOPIA_APP" -type l -print)" == "" ]] || fail "Bundle contém links simbólicos."
[[ "$(/usr/bin/find "$KORNUCOPIA_APP" -perm -022 -print)" == "" ]] || fail "Bundle tem permissões de escrita excessivas."
KORNUCOPIA_EXPECTED=$'Contents/Info.plist\nContents/MacOS/Kornucopia\nContents/Resources/AppIcon.icns\nContents/Resources/Cornucopia.png\nContents/Resources/Localization/en.json\nContents/Resources/Localization/es.json\nContents/Resources/Localization/fr.json\nContents/Resources/Localization/ja.json\nContents/Resources/Localization/pt-BR.json\nContents/_CodeSignature/CodeResources'
KORNUCOPIA_ACTUAL="$(cd "$KORNUCOPIA_APP" && /usr/bin/find Contents -type f -print | LC_ALL=C /usr/bin/sort)"
[[ "$KORNUCOPIA_ACTUAL" == "$KORNUCOPIA_EXPECTED" ]] || fail "Bundle contém arquivos inesperados ou recursos ausentes."
if LC_ALL=C /usr/bin/strings "$KORNUCOPIA_EXECUTABLE" | /usr/bin/grep -E '/Users/|/Volumes/' >/dev/null; then
  fail "O binário contém caminhos locais pessoais."
fi
if /usr/bin/nm "$KORNUCOPIA_EXECUTABLE" 2>/dev/null | /usr/bin/grep -E '(^|[[:space:]])[a-zA-Z]?N_(SO|OSO|FUN)' >/dev/null; then
  fail "O binário contém símbolos de depuração."
fi
/usr/bin/codesign --verify --deep --strict "$KORNUCOPIA_APP"
python3 - "$KORNUCOPIA_ROOT/Resources/Localization" "$KORNUCOPIA_APP/Contents/Resources/Localization" <<'PY'
from collections import Counter
import json
from pathlib import Path
import re
import sys

locales = ("pt-BR", "en", "es", "fr", "ja")
source, bundled = map(Path, sys.argv[1:])
def unique_keys(pairs):
    values = {}
    for key, value in pairs:
        if key in values:
            raise ValueError("Duplicate localization key: " + key)
        values[key] = value
    return values
catalogs = {}
for locale in locales:
    filename = locale + ".json"
    data = json.loads((source / filename).read_text(encoding="utf-8"), object_pairs_hook=unique_keys)
    if not isinstance(data, dict) or not data or any(not isinstance(key, str) or not isinstance(value, str) or not value.strip() for key, value in data.items()):
        raise ValueError("Catalog must contain nonempty string values: " + locale)
    if (source / filename).read_bytes() != (bundled / filename).read_bytes():
        raise ValueError("Bundled catalog differs from source: " + locale)
    catalogs[locale] = data
reference = catalogs["pt-BR"]
for locale, data in catalogs.items():
    if data.keys() != reference.keys():
        raise ValueError("Catalog key parity failed: " + locale)
    for key, value in data.items():
        placeholders = lambda text: Counter(re.findall(r"\{([A-Za-z][A-Za-z0-9_]*)\}", text))
        if placeholders(value) != placeholders(reference[key]):
            raise ValueError("Named placeholder parity failed: " + locale + " / " + key)
print("PASS: five locale catalogs, key parity, placeholders and bundled copies verified")
PY
print "PASS: bundle limpo, arm64, macOS 14, caminhos e permissões verificados"

if ! $KORNUCOPIA_BUNDLE_ONLY; then
  KORNUCOPIA_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  if [[ ! -d "$KORNUCOPIA_SDK" ]]; then KORNUCOPIA_SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"; fi
  KORNUCOPIA_TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/Kornucopia-tests.XXXXXX")"
  trap 'rm -rf "$KORNUCOPIA_TEST_TEMP"' EXIT
  /usr/bin/xcrun swiftc "$KORNUCOPIA_ROOT/Sources/Localization.swift" "$KORNUCOPIA_ROOT/Sources/BoardStore.swift" "$KORNUCOPIA_ROOT/tests/StoreTests.swift" \
    -parse-as-library -O -gnone -sdk "$KORNUCOPIA_SDK" -target arm64-apple-macosx14.0 \
    -o "$KORNUCOPIA_TEST_TEMP/StoreTests"
  "$KORNUCOPIA_TEST_TEMP/StoreTests"
  /usr/bin/xcrun swiftc "$KORNUCOPIA_ROOT/Sources/Localization.swift" "$KORNUCOPIA_ROOT/tests/LocalizationTests.swift" \
    -parse-as-library -O -gnone -sdk "$KORNUCOPIA_SDK" -target arm64-apple-macosx14.0 \
    -o "$KORNUCOPIA_TEST_TEMP/LocalizationTests"
  "$KORNUCOPIA_TEST_TEMP/LocalizationTests" "$KORNUCOPIA_ROOT/Resources/Localization"
fi
