#!/usr/bin/env bash
set -euo pipefail

RESOLUTION="${RESOLUTION:-1440x900}"
START_URL="${START_URL:-https://www.wikipedia.org}"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS:-}"

# --- Wayland session environment -------------------------------------------
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway
# No DRM device and no input devices in the container: drive wlroots headlessly
# and render with pixman (CPU) so no GPU/GBM is required.
export WLR_BACKENDS=headless
export WLR_HEADLESS_OUTPUTS=1
export WLR_RENDERER=pixman
export WLR_LIBINPUT_NO_DEVICES=1
export LIBGL_ALWAYS_SOFTWARE=1

# --- Chromium launcher -------------------------------------------------------
# sway's config parser treats commas as command separators, so the Chromium
# command line lives in its own script rather than inline in sway.conf.
launcher="$XDG_RUNTIME_DIR/start-chromium.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'exec chromium \'
  printf '  %s \\\n' \
    --ozone-platform=wayland \
    '--disable-gpu' \
    '--no-first-run' \
    '--no-default-browser-check' \
    '--disable-features=Translate' \
    '--password-store=basic'
  # shellcheck disable=SC2086
  for f in $CHROMIUM_FLAGS; do printf '  %q \\\n' "$f"; done
  printf '  %q\n' "$START_URL"
} > "$launcher"
chmod +x "$launcher"

# --- Render the sway config --------------------------------------------------
conf="$XDG_RUNTIME_DIR/sway.conf"
sed -e "s|@RESOLUTION@|${RESOLUTION}|g" \
    -e "s|@LAUNCHER@|${launcher}|g" \
    /etc/sway/sway.conf.in > "$conf"

echo "=== chrome-in-container ==="
echo "  resolution : $RESOLUTION"
echo "  start url  : $START_URL"
echo "  extra flags: ${CHROMIUM_FLAGS:-(none)}"
echo "  noVNC      : http://localhost:6080/vnc.html?autoconnect=1&resize=scale"
echo "  VNC        : vnc://localhost:5900"
echo "=========================="

# dbus-run-session gives Chromium a session bus; sway starts wayvnc, websockify
# and chromium itself (see sway.conf.in) so they inherit WAYLAND_DISPLAY.
exec dbus-run-session -- sway -c "$conf" "$@"
