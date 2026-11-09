#!/usr/bin/env bash
# Renders media/logo.svg to the CurseForge avatar (logo-512.png, logo-400.png)
# and the in-game AddOns-list icon (Mailworthy/Textures/Icon.tga: 64x64,
# uncompressed 32-bit, the TGA variant the WoW client loads reliably), and
# media/ui-prototype.html, media/bank-alt-prototype.html, media/bindings-prototype.html and
# media/ux-pass-prototype.html, media/guild-template-prototype.html and media/qol-prototype.html to PNGs, and the CurseForge gallery (media/gallery/*.html,
# authored at 1280x720 and rendered at 1.25x = 1600x900).
# Needs Google Chrome (headless rendering) and Python 3 with Pillow.
# Usage: tools/build-icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() { # <source> <width> <height> <out.png> [scale]
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="${5:-1}" \
    --default-background-color=00000000 --window-size="$2,$3" \
    --screenshot="$4" "file://$PWD/$1" >/dev/null 2>&1
}

render media/logo.svg 512 512 "$tmp/logo.png"

python3 - "$tmp/logo.png" <<'EOF'
import sys
from PIL import Image
src = Image.open(sys.argv[1]).convert("RGBA")
src.save("media/logo-512.png")
src.resize((400, 400), Image.LANCZOS).save("media/logo-400.png")
src.resize((64, 64), Image.LANCZOS).save("Mailworthy/Textures/Icon.tga")  # Pillow writes uncompressed TGA
print("media/logo-512.png, media/logo-400.png, Mailworthy/Textures/Icon.tga")
EOF
# After the logo: the prototype shows logo-512.png.
render media/ui-prototype.html 900 640 media/ui-prototype.png
render media/bank-alt-prototype.html 900 640 media/bank-alt-prototype.png
render media/bindings-prototype.html 1180 850 media/bindings-prototype.png
render media/ux-pass-prototype.html 1580 1290 media/ux-pass-prototype.png
render media/guild-template-prototype.html 1760 1300 media/guild-template-prototype.png
render media/qol-prototype.html 1660 1730 media/qol-prototype.png
echo "media/ui-prototype.png, media/bank-alt-prototype.png, media/bindings-prototype.png, media/ux-pass-prototype.png, media/guild-template-prototype.png, media/qol-prototype.png"
for page in media/gallery/*.html; do
  render "$page" 1280 720 "${page%.html}.png" 1.25
done
echo "media/gallery/*.png (1600x900)"
