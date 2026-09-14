# Chromium on a headless Wayland compositor, streamed over VNC/noVNC.
#
#   sway (wlroots, headless backend, pixman software renderer)
#     └─ chromium --ozone-platform=wayland
#   wayvnc      -> :5900   (native VNC, e.g. macOS Screen Sharing)
#   websockify  -> :6080   (noVNC, view in any browser)
FROM docker.io/library/debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        sway \
        wayvnc \
        chromium \
        chromium-sandbox \
        novnc \
        websockify \
        dbus \
        libgl1-mesa-dri \
        ca-certificates \
        fonts-liberation \
        fonts-noto-color-emoji \
        procps \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Chromium refuses to run as root unless sandboxing is disabled, so use a normal user.
RUN useradd --create-home --uid 1000 --shell /bin/bash chrome

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY sway.conf.in /etc/sway/sway.conf.in
RUN chmod +x /usr/local/bin/entrypoint.sh

USER chrome
WORKDIR /home/chrome

# Screen size of the virtual Wayland output.
ENV RESOLUTION=1440x900
# Page Chromium opens on start.
ENV START_URL=https://www.wikipedia.org
# Extra flags appended to the Chromium command line (e.g. --no-sandbox).
ENV CHROMIUM_FLAGS=""

EXPOSE 5900 6080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
