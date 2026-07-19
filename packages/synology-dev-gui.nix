{
  buildEnv,
  bubblewrap,
  chromium,
  dejavu_fonts,
  fontconfig,
  imagemagick,
  novnc,
  openbox,
  x11vnc,
  xauth,
  xclip,
  xdpyinfo,
  xdotool,
  xvfb,
  xwininfo,
}:
buildEnv {
  name = "synology-dev-gui";
  paths = [
    bubblewrap
    chromium
    dejavu_fonts
    fontconfig
    imagemagick
    novnc
    openbox
    x11vnc
    xauth
    xclip
    xdpyinfo
    xdotool
    xvfb
    xwininfo
  ];
  pathsToLink = [
    "/bin"
    "/share"
  ];
  ignoreCollisions = true;
}
