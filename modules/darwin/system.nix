{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

{
  system.stateVersion = 7;
  system.primaryUser = username;
  users.users.${username}.home = homeDirectory;

  # The Mini uses Determinate Nix. Let the host installer own /etc/nix instead
  # of nix-darwin's native Nix module, which aborts when Determinate is present.
  nix.enable = false;

  # Homebrew is an integration point for host applications. Never remove or
  # zap unmanaged software during activation; package selections come later.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    # Host applications are intentionally kept here instead of the shared
    # Home Manager profile. Existing applications are never removed.
    brews = [
      "et"
      "mosh"
      "tailscale"
      "tsshd"
    ];
    casks = [
      # Approved Mac-only applications.
      "codex-app"
      "chatgpt"
      "claude"
      "mos"

      # Shared GUI intent, installed by the host package manager on macOS.
      "font-jetbrains-mono-nerd-font"
      "zed"
      "sublime-text"
      "cursor"
      "visual-studio-code"
      "vlc"
      "google-chrome"
      "hyper"
      "godot"
    ];
  };

  # ProxyBridge and Mac App Store apps stay manual on Apple Silicon:
  # - proxybridge cask v4.x requires Rosetta for its .pkg installer
  # - mas installs need interactive App Store sign-in and block activation
  # Reviewed ProxyBridge defaults live in templates/proxybridge.
}
