# chrome-in-container

Chromium running on a **headless Wayland compositor** inside a Podman container,
viewable from macOS.

```
  macOS                        │  podman machine (Linux VM)  │  container
  ─────────────────────────────┼─────────────────────────────┼──────────────────────
  Safari/Chrome  → :6080 ──────┼─────────────────────────────┼─→ websockify + noVNC
  Screen Sharing → :5900 ──────┼─────────────────────────────┼─→ wayvnc
                               │                             │     ↑ wlr-screencopy
                               │                             │   sway (headless, pixman)
                               │                             │     └─ chromium --ozone-platform=wayland
```

No X11 anywhere: `xwayland` is disabled and Chromium speaks the Wayland protocol
natively. wlroots uses its `headless` backend with the `pixman` software renderer,
so no DRM device or GPU passthrough is needed.

## Quick start

```sh
chmod +x run.sh entrypoint.sh   # see note below
./run.sh
```

> **Note on file permissions.** These sources were uploaded through the GitHub web
> UI, which cannot preserve the executable bit, so `run.sh` and `entrypoint.sh`
> arrive as mode `100644`. Run `chmod +x run.sh entrypoint.sh` once after cloning
> (or just use `bash run.sh`). `entrypoint.sh` is re-marked executable inside the
> image by the `Containerfile`, so the container itself is unaffected.

That creates the podman machine if missing, builds the image, starts the
container, and opens noVNC in your Mac browser.

## Commands

| Command | Effect |
| --- | --- |
| `./run.sh` | build (if needed) + start + open the viewer |
| `./run.sh build` | (re)build the image |
| `./run.sh up` | start the container |
| `./run.sh down` | stop and remove the container |
| `./run.sh restart` | `down` then `up` |
| `./run.sh logs` | follow container logs |
| `./run.sh status` | container state |
| `./run.sh shell` | bash inside the running container |
| `./run.sh url` | print the viewing URLs |
| `./run.sh open` | open noVNC in your default browser |
| `./run.sh screenshare` | open macOS Screen Sharing on `vnc://localhost:5900` |

## Viewing

- **Browser (no extra software):** <http://localhost:6080/vnc.html?autoconnect=1&resize=scale>
- **Native VNC:** `vnc://localhost:5900` — Finder → Go → Connect to Server, or
  `./run.sh screenshare`. Snappier than noVNC. No password.

Both ports are published to `127.0.0.1` on the Mac only, so nothing is reachable
from your network.

## Configuration

Environment variables read by `run.sh`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `RESOLUTION` | `1440x900` | size of the virtual Wayland output |
| `START_URL` | `https://www.wikipedia.org` | page Chromium opens |
| `NOVNC_PORT` | `6080` | host port for the browser viewer |
| `VNC_PORT` | `5900` | host port for native VNC |
| `IMAGE` / `NAME` | `chrome-wayland` | image tag / container name |
| `CHROME_NO_SANDBOX` | `0` | set to `1` to add `--no-sandbox` |
| `MACHINE_CPUS` / `MACHINE_MEMORY` / `MACHINE_DISK` | `4` / `4096` / `20` | VM size, used only when creating the machine |

```sh
RESOLUTION=1920x1080 START_URL=https://news.ycombinator.com ./run.sh restart
```

Changing `RESOLUTION` needs a `restart`; it is applied to the `HEADLESS-1` output
by the sway config.

## Files

- `Containerfile` — Debian trixie + sway, wayvnc, chromium, noVNC. Also works as a
  Dockerfile (`podman build -f Containerfile .`).
- `entrypoint.sh` — sets up the headless Wayland env, writes the Chromium launcher
  and the sway config, then runs `dbus-run-session -- sway`.
- `sway.conf.in` — template: output geometry, no decorations, and the `exec` lines
  that start wayvnc, websockify and Chromium.
- `run.sh` — machine/build/run/lifecycle wrapper.

## Notes

- **Chromium runs as uid 1000 (`chrome`), not root**, so its sandbox stays on. The
  container runs with `--cap-drop=ALL` and `--security-opt seccomp=unconfined`; the
  latter is what lets Chromium create the unprivileged user namespaces its sandbox
  needs. If you ever see `Failed to move to new namespace`, run with
  `CHROME_NO_SANDBOX=1`.
- `--shm-size=2g` — Chromium crashes with podman's default 64 MB `/dev/shm`.
- **Harmless log noise:** `drmGetDevices2() has not found any devices` (no GPU is
  exposed) and `Failed to connect to socket /run/dbus/system_bus_socket` (no system
  bus in the container; Chromium only needs the session bus, which
  `dbus-run-session` provides).
- **No persistent profile.** The container is disposable — `./run.sh down` discards
  cookies and logins. To keep them, add a volume for `/home/chrome/.config/chromium`
  in `run.sh`.
- sway's config parser treats `,` as a command separator, which is why the Chromium
  command line is generated into `start-chromium.sh` rather than inlined into
  `sway.conf` — URLs and flags frequently contain commas.
