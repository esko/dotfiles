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
  xclip,
  xdotool,
  xorg,
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
    xclip
    xdotool
    xorg.xauth
    xorg.xdpyinfo
    xorg.xvfb
    xorg.xwininfo
  ];
  pathsToLink = [
    "/bin"
    "/share"
  ];
  ignoreCollisions = true;
}
