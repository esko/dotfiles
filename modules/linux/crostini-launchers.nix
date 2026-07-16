{ lib, pkgs, username, inkscapeBeta ? null, ... }:

# Publish Baguette GUI launchers into /usr/local/share/applications via
# systemd-tmpfiles. That directory is always on cros-garcon's default
# XDG_DATA_DIRS, so ChromeOS sees the apps even when the user drop-in fails.
let
  cursorPackage = if builtins.hasAttr "code-cursor" pkgs then pkgs.code-cursor else null;
  antigravityPackage = if builtins.hasAttr "antigravity" pkgs then pkgs.antigravity else null;
  inkscapeStable = if builtins.hasAttr "inkscape" pkgs then pkgs.inkscape else null;
  inkscapeDev = inkscapeBeta;

  mkLauncher =
    { name
    , desktopName
    , package
    , categories
    , comment ? null
    , genericName ? null
    , mimeTypes ? [ ]
    , icon ? name
    }:
    {
      inherit name;
      item = pkgs.makeDesktopItem {
        inherit name desktopName categories icon;
        inherit comment genericName mimeTypes;
        exec = "${lib.getExe package} %F";
        tryExec = lib.getExe package;
        terminal = false;
        startupNotify = true;
        type = "Application";
      };
    };

  launcherSpecs = lib.filter (x: x != null) [
    (if cursorPackage != null then mkLauncher {
      name = "cursor";
      desktopName = "Cursor";
      package = cursorPackage;
      genericName = "Text Editor";
      comment = "AI-powered code editor";
      categories = [ "Development" "TextEditor" ];
      mimeTypes = [ "application/x-cursor-workspace" "inode/directory" "text/plain" ];
      icon = "cursor";
    } else null)
    (if antigravityPackage != null then mkLauncher {
      name = "antigravity";
      desktopName = "Antigravity";
      package = antigravityPackage;
      genericName = "IDE";
      comment = "Agentic development platform";
      categories = [ "Development" "IDE" ];
      icon = "antigravity";
    } else null)
    (if inkscapeStable != null then mkLauncher {
      name = "inkscape";
      desktopName = "Inkscape";
      package = inkscapeStable;
      genericName = "Vector Graphics Editor";
      comment = "Inkscape ${inkscapeStable.version or "1.4"} (stable)";
      categories = [ "Graphics" "VectorGraphics" "2DGraphics" ];
      mimeTypes = [
        "image/svg+xml"
        "image/svg+xml-compressed"
        "application/vnd.corel-draw"
        "application/pdf"
        "image/png"
        "image/jpeg"
      ];
      icon = "inkscape";
    } else null)
    (if inkscapeDev != null then mkLauncher {
      name = "inkscape-beta";
      desktopName = "Inkscape 1.5 Beta";
      package = inkscapeDev;
      genericName = "Vector Graphics Editor";
      comment = "Inkscape 1.5 development AppImage";
      categories = [ "Graphics" "VectorGraphics" "2DGraphics" ];
      mimeTypes = [
        "image/svg+xml"
        "image/svg+xml-compressed"
        "application/vnd.corel-draw"
        "application/pdf"
        "image/png"
        "image/jpeg"
      ];
      icon = "inkscape";
    } else null)
  ];

  launchers = pkgs.symlinkJoin {
    name = "baguette-crostini-launchers";
    paths = map (spec: spec.item) launcherSpecs;
  };

  desktopNames = map (spec: spec.name) launcherSpecs;
in
{
  environment.systemPackages = lib.optional (launcherSpecs != [ ]) launchers;
  environment.pathsToLink = [ "/share" ];

  systemd.tmpfiles.rules = [
    "d /usr/local/share/applications 0755 root root -"
  ] ++ map (
    name: "L+ /usr/local/share/applications/${name}.desktop - - - - ${launchers}/share/applications/${name}.desktop"
  ) desktopNames;

  # After system-manager applies tmpfiles, nudge the user garcon service so the
  # ChromeOS host picks up /usr/local launchers without a full container reboot.
  systemd.services.baguette-refresh-crostini-launchers = lib.mkIf (launcherSpecs != [ ]) {
    description = "Refresh ChromeOS cros-garcon after publishing Baguette launchers";
    wantedBy = [ "system-manager.target" ];
    after = [ "system-manager-path.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = username;
      ExecStart = pkgs.writeShellScript "baguette-refresh-crostini-launchers" ''
        set -euo pipefail
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if command -v systemctl >/dev/null 2>&1; then
          systemctl --user daemon-reload 2>/dev/null || true
          systemctl --user restart cros-garcon.service 2>/dev/null || true
        fi
        ls -l /usr/local/share/applications/cursor.desktop \
          /usr/local/share/applications/antigravity.desktop \
          /usr/local/share/applications/inkscape.desktop \
          /usr/local/share/applications/inkscape-beta.desktop 2>/dev/null || true
      '';
    };
  };
}
