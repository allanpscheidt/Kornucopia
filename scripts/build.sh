#!/bin/zsh
set -euo pipefail
umask 022

KORNUCOPIA_ROOT="${0:A:h:h}"
KORNUCOPIA_BUILD="$KORNUCOPIA_ROOT/build"
KORNUCOPIA_BUNDLE="$KORNUCOPIA_BUILD/Kornucopia.app"
KORNUCOPIA_BUNDLE_ID="net.allanpscheidt.kornucopia"
KORNUCOPIA_INSTALL=false

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--install" ) ]]; then
  print -u2 "Uso: scripts/build.sh [--install]"
  exit 2
fi
if [[ $# -eq 1 ]]; then KORNUCOPIA_INSTALL=true; fi

is_app_running() {
  local expected="$1/Contents/MacOS/Kornucopia"
  local process_command
  while IFS= read -r process_command; do
    if [[ "$process_command" == "$expected" ]]; then return 0; fi
  done < <(/bin/ps -axo comm=)
  return 1
}

# Use the working installed SDK for this build only. Current CLT macOS 27
# installations can lack the SwiftUI macro plugin. No global setting changes.
KORNUCOPIA_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ ! -d "$KORNUCOPIA_SDK" ]]; then
  KORNUCOPIA_SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi
mkdir -p "$KORNUCOPIA_BUILD"
KORNUCOPIA_STAGE="$(mktemp -d "$KORNUCOPIA_BUILD/.Kornucopia-build.XXXXXX")"
trap 'rm -rf "$KORNUCOPIA_STAGE"' EXIT
KORNUCOPIA_STAGED_APP="$KORNUCOPIA_STAGE/Kornucopia.app"
mkdir -p "$KORNUCOPIA_STAGED_APP/Contents/MacOS" "$KORNUCOPIA_STAGED_APP/Contents/Resources"

if [[ ! -f "$KORNUCOPIA_ROOT/Resources/AppIcon.icns" || ! -f "$KORNUCOPIA_ROOT/Resources/Cornucopia.png" ]]; then
  /usr/bin/xcrun swift "$KORNUCOPIA_ROOT/scripts/generate_icon.swift" "$KORNUCOPIA_STAGE/AppIcon.iconset" "$KORNUCOPIA_ROOT/Resources/Cornucopia.png"
  /usr/bin/iconutil --convert icns "$KORNUCOPIA_STAGE/AppIcon.iconset" --output "$KORNUCOPIA_ROOT/Resources/AppIcon.icns"
fi

/usr/bin/xcrun swiftc "$KORNUCOPIA_ROOT"/Sources/*.swift \
  -parse-as-library -O -gnone \
  -file-prefix-map "$KORNUCOPIA_ROOT=." \
  -sdk "$KORNUCOPIA_SDK" \
  -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit \
  -o "$KORNUCOPIA_STAGED_APP/Contents/MacOS/Kornucopia"
/usr/bin/strip -S "$KORNUCOPIA_STAGED_APP/Contents/MacOS/Kornucopia"

cp "$KORNUCOPIA_ROOT/Resources/AppIcon.icns" "$KORNUCOPIA_STAGED_APP/Contents/Resources/AppIcon.icns"
cp "$KORNUCOPIA_ROOT/Resources/Cornucopia.png" "$KORNUCOPIA_STAGED_APP/Contents/Resources/Cornucopia.png"
mkdir -p "$KORNUCOPIA_STAGED_APP/Contents/Resources/Localization"
for KORNUCOPIA_LANGUAGE in pt-BR en es fr ja; do
  cp "$KORNUCOPIA_ROOT/Resources/Localization/$KORNUCOPIA_LANGUAGE.json" "$KORNUCOPIA_STAGED_APP/Contents/Resources/Localization/$KORNUCOPIA_LANGUAGE.json"
done
KORNUCOPIA_PLIST="$KORNUCOPIA_STAGED_APP/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string pt_BR "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string Kornucopia "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "$KORNUCOPIA_BUNDLE_ID" "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleName -string Kornucopia "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string Kornucopia "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string 1.0.2 "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleVersion -string 3 "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleLocalizations -json '["pt-BR","en","es","fr","ja"]' "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert LSApplicationCategoryType -string public.app-category.productivity "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert NSHighResolutionCapable -bool YES "$KORNUCOPIA_PLIST"
/usr/bin/plutil -insert NSHumanReadableCopyright -string 'Allan Pscheidt' "$KORNUCOPIA_PLIST"
/usr/bin/plutil -lint "$KORNUCOPIA_PLIST"
/usr/bin/find "$KORNUCOPIA_STAGED_APP" -type d -exec chmod 755 {} +
/usr/bin/find "$KORNUCOPIA_STAGED_APP" -type f -exec chmod 644 {} +
chmod 755 "$KORNUCOPIA_STAGED_APP/Contents/MacOS/Kornucopia"
/usr/bin/codesign --force --sign - "$KORNUCOPIA_STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$KORNUCOPIA_STAGED_APP"

if [[ -L "$KORNUCOPIA_BUNDLE" ]]; then
  print -u2 "Build interrompido: o destino é um link simbólico."
  exit 1
fi
if is_app_running "$KORNUCOPIA_BUNDLE"; then
  print -u2 "Feche o Kornucopia aberto na pasta build antes de substituir o app."
  exit 1
fi
if [[ -e "$KORNUCOPIA_BUNDLE" ]]; then rm -rf "$KORNUCOPIA_BUNDLE"; fi
mv "$KORNUCOPIA_STAGED_APP" "$KORNUCOPIA_BUNDLE"
print "App criado: $KORNUCOPIA_BUNDLE"

if $KORNUCOPIA_INSTALL; then
  KORNUCOPIA_DESTINATION="/Applications/Kornucopia.app"
  if [[ -L "$KORNUCOPIA_DESTINATION" ]]; then
    print -u2 "Instalação interrompida: o destino é um link simbólico."
    exit 1
  fi
  if is_app_running "$KORNUCOPIA_DESTINATION"; then
    print -u2 "Feche o Kornucopia pelo menu Encerrar antes de instalar a atualização."
    exit 1
  fi
  if [[ -e "$KORNUCOPIA_DESTINATION" ]]; then
    KORNUCOPIA_EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$KORNUCOPIA_DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$KORNUCOPIA_EXISTING_ID" != "$KORNUCOPIA_BUNDLE_ID" ]]; then
      print -u2 "Instalação interrompida: /Applications/Kornucopia.app pertence a outro app."
      exit 1
    fi
  fi
  /usr/bin/ditto --norsrc --noextattr --noacl "$KORNUCOPIA_BUNDLE" "$KORNUCOPIA_DESTINATION"
  /usr/bin/codesign --verify --deep --strict "$KORNUCOPIA_DESTINATION"
  print "App instalado: $KORNUCOPIA_DESTINATION"
fi
