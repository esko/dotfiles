{ lib, pkgs, ... }:

let
  inherit (lib) mkIf mkMerge;

  # Tiny theme seeds. Darwin Homebrew apps read Application Support; Linux
  # (and XDG-aware builds) read ~/.config.
  managed = source: {
    inherit source;
    force = true;
  };

  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  # Cursor ships on Baguette (Nix) and Mini (Homebrew).
  home.file = mkMerge [
    (mkIf isDarwin {
      "Library/Application Support/Cursor/User/settings.json" =
        managed ../../config/editors/cursor/settings.json;
      "Library/Application Support/Code/User/settings.json" =
        managed ../../config/editors/vscode/settings.json;
      "Library/Application Support/Zed/settings.json" =
        managed ../../config/editors/zed/settings.json;
      "Library/Application Support/Sublime Text/Packages/User/Preferences.sublime-settings" =
        managed ../../config/editors/sublime-text/Preferences.sublime-settings;
    })
    (mkIf (!isDarwin) {
      ".config/Cursor/User/settings.json" =
        managed ../../config/editors/cursor/settings.json;
      # VS Code / Zed / Sublime are Mini casks today; keep Linux XDG seeds so a
      # future apt/Nix install picks up the same theme without a second module.
      ".config/Code/User/settings.json" =
        managed ../../config/editors/vscode/settings.json;
      ".config/zed/settings.json" =
        managed ../../config/editors/zed/settings.json;
      ".config/sublime-text/Packages/User/Preferences.sublime-settings" =
        managed ../../config/editors/sublime-text/Preferences.sublime-settings;
    })
  ];
}
