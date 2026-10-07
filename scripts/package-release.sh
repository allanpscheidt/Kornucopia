#!/bin/zsh
set -euo pipefail
umask 022

if [[ $# -ne 0 ]]; then
  print -u2 "Uso: scripts/package-release.sh"
  exit 2
fi
KORNUCOPIA_ROOT="${0:A:h:h}"
KORNUCOPIA_APP="$KORNUCOPIA_ROOT/build/Kornucopia.app"
KORNUCOPIA_DIST="$KORNUCOPIA_ROOT/dist"

"$KORNUCOPIA_ROOT/scripts/build.sh"
"$KORNUCOPIA_ROOT/scripts/test.sh" "$KORNUCOPIA_APP"
KORNUCOPIA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$KORNUCOPIA_APP/Contents/Info.plist")"
[[ "$KORNUCOPIA_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 "Versão inválida para o arquivo de release."; exit 1; }
KORNUCOPIA_NAME="Kornucopia-v$KORNUCOPIA_VERSION-macOS-arm64.zip"
mkdir -p "$KORNUCOPIA_DIST"
KORNUCOPIA_RELEASE_STAGE="$(mktemp -d "$KORNUCOPIA_DIST/.Kornucopia-release.XXXXXX")"
trap 'rm -rf "$KORNUCOPIA_RELEASE_STAGE"' EXIT
/usr/bin/ditto --norsrc --noextattr --noacl "$KORNUCOPIA_APP" "$KORNUCOPIA_RELEASE_STAGE/Kornucopia.app"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent \
  "$KORNUCOPIA_RELEASE_STAGE/Kornucopia.app" "$KORNUCOPIA_RELEASE_STAGE/$KORNUCOPIA_NAME"
if /usr/bin/unzip -Z1 "$KORNUCOPIA_RELEASE_STAGE/$KORNUCOPIA_NAME" | /usr/bin/grep -Ev '^Kornucopia\.app(/|$)' >/dev/null; then
  print -u2 "O ZIP contém arquivos fora do app."
  exit 1
fi
mkdir "$KORNUCOPIA_RELEASE_STAGE/verify"
/usr/bin/ditto -x -k --norsrc --noextattr --noacl "$KORNUCOPIA_RELEASE_STAGE/$KORNUCOPIA_NAME" "$KORNUCOPIA_RELEASE_STAGE/verify"
"$KORNUCOPIA_ROOT/scripts/test.sh" --bundle-only "$KORNUCOPIA_RELEASE_STAGE/verify/Kornucopia.app"
mv -f "$KORNUCOPIA_RELEASE_STAGE/$KORNUCOPIA_NAME" "$KORNUCOPIA_DIST/$KORNUCOPIA_NAME"
(cd "$KORNUCOPIA_DIST" && /usr/bin/shasum -a 256 "$KORNUCOPIA_NAME" > SHA256SUMS.txt && /usr/bin/shasum -a 256 -c SHA256SUMS.txt)
print "Release criado: $KORNUCOPIA_DIST/$KORNUCOPIA_NAME"
