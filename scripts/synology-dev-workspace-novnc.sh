#!/usr/bin/env bash
set -euo pipefail

# Attach a browser-based viewer to an existing X11 display inside the
# container, typically the hidden workspace display created by
# agent-workspace-linux.
display=${SYNOLOGY_DEV_DISPLAY:-${DISPLAY:-:99}}
vnc_port=${SYNOLOGY_DEV_VNC_PORT:-5900}
novnc_port=${SYNOLOGY_DEV_NOVNC_PORT:-6080}
novnc_web=${SYNOLOGY_DEV_NOVNC_WEB:-/share/novnc}

export DISPLAY="$display"

if ! command -v x11vnc >/dev/null 2>&1; then
  printf '%s\n' 'x11vnc is not available' >&2
  exit 1
fi

if ! command -v websockify >/dev/null 2>&1 || [[ ! -d "$novnc_web" ]]; then
  printf '%s\n' 'websockify or noVNC web assets are not available' >&2
  exit 1
fi

x11vnc_args=(
  -display "$display"
  -forever
  -shared
  -rfbport "$vnc_port"
  -localhost no
  -noxdamage
)
if [[ -n "${SYNOLOGY_DEV_VNC_PASSWORD:-}" ]]; then
  x11vnc_args+=(-passwd "$SYNOLOGY_DEV_VNC_PASSWORD")
else
  x11vnc_args+=(-nopw)
fi

x11vnc "${x11vnc_args[@]}" &
websockify --web "$novnc_web" "$novnc_port" "localhost:$vnc_port"
