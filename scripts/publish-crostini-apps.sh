#!/usr/bin/env bash
# Publish Baguette GUI .desktop files where ChromeOS cros-garcon will see them.
# Safe to re-run. Prefers /usr/local/share/applications (always searched) and
# also materializes copies under ~/.local/share/applications.
set -euo pipefail

username="${USER:-esko}"
home_dir="${HOME:-/home/$username}"
local_apps="$home_dir/.local/share/applications"
system_apps=/usr/local/share/applications
profile_bin="/etc/profiles/per-user/$username/bin"
garcon_dropin="$home_dir/.config/systemd/user/cros-garcon.service.d/override.conf"

resolve_bin() {
  local name=$1
  local candidate
  for candidate in \
    "$profile_bin/$name" \
    "$home_dir/.nix-profile/bin/$name" \
    "$home_dir/.local/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  return 1
}

write_desktop() {
  local dest=$1
  local app_id=$2
  local name=$3
  local exec_path=$4
  local categories=$5
  local comment=$6
  local icon=$7

  cat >"$dest" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$comment
Exec=$exec_path %F
TryExec=$exec_path
Icon=$icon
Terminal=false
Categories=$categories
StartupNotify=true
EOF
}

mkdir -p "$local_apps" "$(dirname "$garcon_dropin")"

cat >"$garcon_dropin" <<EOF
[Service]
Environment="PATH=$home_dir/.local/bin:$profile_bin:$home_dir/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/local/games:/usr/sbin:/usr/bin:/usr/games:/sbin:/bin"
Environment="XDG_DATA_DIRS=/etc/profiles/per-user/$username/share:$home_dir/.nix-profile/share:$home_dir/.local/share:$home_dir/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
EOF

declare -a published=()
declare -a missing=()

publish_one() {
  local app_id=$1
  local display_name=$2
  local bin_name=$3
  local categories=$4
  local comment=$5
  local icon=$6
  local exec_path dest_local dest_system

  if ! exec_path=$(resolve_bin "$bin_name"); then
    missing+=("$bin_name")
    printf 'skip %s (binary not found)\n' "$app_id" >&2
    return 0
  fi

  dest_local="$local_apps/$app_id.desktop"
  write_desktop "$dest_local" "$app_id" "$display_name" "$exec_path" "$categories" "$comment" "$icon"
  published+=("$dest_local -> $exec_path")

  if mkdir -p "$system_apps" 2>/dev/null && [[ -w "$system_apps" ]]; then
    write_desktop "$system_apps/$app_id.desktop" "$app_id" "$display_name" "$exec_path" "$categories" "$comment" "$icon"
    published+=("$system_apps/$app_id.desktop")
  elif command -v sudo >/dev/null 2>&1; then
    tmp=$(mktemp)
    write_desktop "$tmp" "$app_id" "$display_name" "$exec_path" "$categories" "$comment" "$icon"
    sudo mkdir -p "$system_apps"
    sudo install -m 0644 "$tmp" "$system_apps/$app_id.desktop"
    rm -f "$tmp"
    published+=("$system_apps/$app_id.desktop (sudo)")
  else
    printf 'warning: cannot write %s/%s.desktop\n' "$system_apps" "$app_id" >&2
  fi
}

publish_one cursor Cursor cursor 'Development;TextEditor;' 'AI-powered code editor' cursor
publish_one antigravity Antigravity antigravity 'Development;IDE;' 'Agentic development platform' antigravity
publish_one inkscape Inkscape inkscape 'Graphics;VectorGraphics;2DGraphics;' 'Inkscape stable' inkscape
publish_one inkscape-beta 'Inkscape 1.5 Beta' inkscape-beta 'Graphics;VectorGraphics;2DGraphics;' 'Inkscape 1.5 development AppImage' inkscape

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$local_apps" 2>/dev/null || true
fi

touch "$local_apps" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user restart cros-garcon.service 2>/dev/null || true
fi

printf '\nPublished launchers:\n'
if ((${#published[@]})); then
  printf '  %s\n' "${published[@]}"
else
  printf '  (none)\n'
fi

if ((${#missing[@]})); then
  printf '\nMissing binaries (activate baguette GUI apps first):\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
fi

printf '\nDiagnostics:\n'
printf '  garcon drop-in: %s\n' "$garcon_dropin"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user show cros-garcon.service -p Environment --no-pager 2>/dev/null | head -5 || true
fi
ls -l "$local_apps"/{cursor,antigravity,inkscape,inkscape-beta}.desktop 2>/dev/null || true
ls -l "$system_apps"/{cursor,antigravity,inkscape,inkscape-beta}.desktop 2>/dev/null || true

cat <<'EOF'

If ChromeOS still shows no Linux apps: Settings → Developers → Linux development
environment → Stop, then Start (or reboot the Chromebook). Garcon's host app
list often needs a container restart after first publish.
EOF
