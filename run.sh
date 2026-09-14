#!/usr/bin/env bash
#
# Build and run Chromium-on-Wayland in a podman container and view it from macOS.
#
#   ./run.sh              build if needed, start the container, open noVNC
#   ./run.sh build        (re)build the image
#   ./run.sh up           start the container
#   ./run.sh down         stop and remove the container
#   ./run.sh restart      down + up
#   ./run.sh logs         follow container logs
#   ./run.sh status       show container state
#   ./run.sh shell        interactive shell inside the running container
#   ./run.sh url          print the viewing URLs
#   ./run.sh open         open noVNC in the default macOS browser
#   ./run.sh viewer       launch a native VNC client (TigerVNC), if installed
#
# Environment overrides:
#   IMAGE=chrome-wayland        image tag
#   NAME=chrome-wayland         container name
#   RESOLUTION=1440x900         virtual screen size
#   START_URL=https://...       page Chromium opens
#   NOVNC_PORT=6080  VNC_PORT=5900
#   CHROME_NO_SANDBOX=1         add --no-sandbox (only if the sandbox fails)
#   MACHINE_CPUS=4 MACHINE_MEMORY=4096 MACHINE_DISK=20

set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${IMAGE:-chrome-wayland}"
NAME="${NAME:-chrome-wayland}"
RESOLUTION="${RESOLUTION:-1440x900}"
START_URL="${START_URL:-https://www.wikipedia.org}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5900}"
CHROME_NO_SANDBOX="${CHROME_NO_SANDBOX:-0}"
MACHINE_CPUS="${MACHINE_CPUS:-4}"
MACHINE_MEMORY="${MACHINE_MEMORY:-4096}"
MACHINE_DISK="${MACHINE_DISK:-20}"

NOVNC_URL="http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=scale"
VNC_URL="vnc://localhost:${VNC_PORT}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# --- podman machine ----------------------------------------------------------
# On macOS podman runs containers inside a Linux VM; make sure one is up.
ensure_machine() {
  command -v podman >/dev/null || die "podman not found. Install it with: brew install podman"
  [ "$(uname -s)" = "Darwin" ] || return 0

  if ! podman machine list --format '{{.Name}}' | grep -q .; then
    log "No podman machine found — creating one (${MACHINE_CPUS} cpus, ${MACHINE_MEMORY}MB, ${MACHINE_DISK}GB)"
    podman machine init --cpus "$MACHINE_CPUS" --memory "$MACHINE_MEMORY" --disk-size "$MACHINE_DISK"
  fi

  if ! podman machine list --format '{{.Name}} {{.LastUp}}' | grep -qi 'currently running'; then
    log "Starting podman machine"
    podman machine start
  fi
}

image_exists()     { podman image exists "$IMAGE"; }
container_exists() { podman container exists "$NAME"; }
container_running(){ [ "$(podman inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" = "true" ]; }

# --- commands ----------------------------------------------------------------
cmd_build() {
  ensure_machine
  log "Building $IMAGE"
  podman build -t "$IMAGE" -f Containerfile .
}

cmd_up() {
  ensure_machine
  image_exists || cmd_build

  if container_running; then
    log "Container '$NAME' is already running"
    cmd_url
    return 0
  fi
  container_exists && podman rm -f "$NAME" >/dev/null

  local flags=""
  [ "$CHROME_NO_SANDBOX" = "1" ] && flags="--no-sandbox"

  log "Starting container '$NAME'"
  podman run -d \
    --name "$NAME" \
    --hostname chrome-box \
    -p "127.0.0.1:${NOVNC_PORT}:6080" \
    -p "127.0.0.1:${VNC_PORT}:5900" \
    -e RESOLUTION="$RESOLUTION" \
    -e START_URL="$START_URL" \
    -e CHROMIUM_FLAGS="$flags" \
    --shm-size=2g \
    --security-opt seccomp=unconfined \
    --cap-drop=ALL \
    "$IMAGE" >/dev/null

  log "Waiting for the noVNC endpoint"
  local i
  for i in $(seq 1 60); do
    if curl -sf -o /dev/null "http://localhost:${NOVNC_PORT}/vnc.html"; then
      cmd_url
      return 0
    fi
    container_running || { podman logs "$NAME"; die "Container exited during startup"; }
    sleep 1
  done
  warn "noVNC did not answer within 60s. Recent logs:"
  podman logs --tail 40 "$NAME"
  exit 1
}

cmd_down() {
  container_exists || { log "No container named '$NAME'"; return 0; }
  log "Removing container '$NAME'"
  podman rm -f "$NAME" >/dev/null
}

cmd_url() {
  cat <<EOF

  Browser (noVNC):   ${NOVNC_URL}
  Native VNC:        ${VNC_URL}      (needs a client that supports no-auth VNC;
                                       macOS Screen Sharing does NOT -- see ./run.sh viewer)

  ./run.sh open          view it now
  ./run.sh logs          follow logs
  ./run.sh down          stop it

EOF
}

cmd_open()        { open "$NOVNC_URL"; }

# wayvnc only offers RFB security type 1 ("None"). macOS Screen Sharing requires
# VNC Auth or Apple's ARD types and fails with "Connection failed to localhost",
# so it can't be used here. Launch a client that does support no-auth VNC.
cmd_viewer() {
  local bin
  for bin in vncviewer /Applications/TigerVNC\ Viewer.app/Contents/MacOS/TigerVNC\ Viewer; do
    if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
      log "Launching $bin"
      "$bin" "localhost:${VNC_PORT}" &
      return 0
    fi
  done
  cat >&2 <<EOF

No no-auth-capable VNC client found.

  macOS Screen Sharing cannot connect to this container. wayvnc offers only RFB
  security type 1 ("None"), and Apple's client requires VNC Auth or ARD. wayvnc
  supports TLS and RSA-AES instead, neither of which Apple's client speaks, so
  adding a password would not help.

Use the browser viewer instead (no install, works today):

  ./run.sh open        ${NOVNC_URL}

Or install a compatible native client:

  brew install --cask tigervnc-viewer   # then: ./run.sh viewer

EOF
  return 1
}
cmd_logs()        { podman logs -f "$NAME"; }
cmd_status()      { podman ps -a --filter "name=^${NAME}$"; }
cmd_shell()       { podman exec -it "$NAME" bash; }

case "${1:-default}" in
  default)     cmd_up; cmd_open ;;
  build)       cmd_build ;;
  up|start)    cmd_up ;;
  down|stop)   cmd_down ;;
  restart)     cmd_down; cmd_up ;;
  logs)        cmd_logs ;;
  status)      cmd_status ;;
  shell)       cmd_shell ;;
  url)         cmd_url ;;
  open)        cmd_open ;;
  viewer)      cmd_viewer ;;
  screenshare) warn "macOS Screen Sharing cannot connect to wayvnc (no-auth VNC)."; cmd_viewer ;;
  *)           die "Unknown command '$1'. See the header of $0 for usage." ;;
esac
