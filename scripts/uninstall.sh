#!/bin/bash
# Wipes Flying Toasters completely so the next install starts clean:
#   - kills host processes
#   - removes user + system .saver bundles
#   - removes the new file-backed prefs plist (v1.3+)
#   - removes legacy NSUserDefaults storage (pre-1.3)
#   - sweeps macOS 26 sandboxed extension containers
#   - sweeps wallpaper.agent thumbnail/preview caches
#   - verifies nothing is left

set -u

echo "== Killing host processes =="
killall -v "System Settings" Wallpaper WallpaperLegacyExtension legacyScreenSaver wallpaper.agent 2>/dev/null || true

echo
echo "== User-level bundle and prefs =="
rm -rfv "$HOME/Library/Screen Savers/Flying Toasters.saver"
rm -fv  "$HOME/Library/Screen Savers/Flying Toasters.prefs.plist"

echo
echo "== Legacy NSUserDefaults storage =="
defaults -currentHost delete "Flying Toasters" 2>/dev/null || true
rm -fv "$HOME"/Library/Preferences/ByHost/Flying\ Toasters.*.plist 2>/dev/null || true

echo
echo "== Sandbox-extension containers =="
for d in \
  "$HOME/Library/Containers/com.apple.Wallpaper-Settings.extension" \
  "$HOME/Library/Containers/com.apple.wallpaper.extension.legacy" \
  "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver" \
  "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver.x86-64"
do
  [ -d "$d" ] && find "$d" -iname "*lying*oaster*" -print -exec rm -rfv {} + 2>/dev/null
done

echo
echo "== wallpaper.agent caches =="
CACHE="$HOME/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches"
[ -d "$CACHE" ] && find "$CACHE" -iname "*lying*oaster*" -print -exec rm -rfv {} + 2>/dev/null

echo
echo "== System-level install =="
SYS="/Library/Screen Savers/Flying Toasters.saver"
if [ -e "$SYS" ]; then
  echo "Found $SYS - sudo needed to remove"
  sudo rm -rfv "$SYS"
else
  echo "no /Library/Screen Savers install"
fi

echo
echo "== Verification - anything left? =="
find "$HOME/Library" /Library -iname "*lying*oaster*" 2>/dev/null \
  | grep -vE "/Developer/|/CocoaPods/|/CloudStorage/"
echo "(empty after the grep = clean; source repo at ~/Developer/FlyingToasters is intentionally not touched)"
