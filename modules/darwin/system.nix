{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

{
  system.stateVersion = 7;
  system.primaryUser = username;
  users.users.${username}.home = homeDirectory;

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
      "tsshd"
    ];
    casks = [
      # Approved Mac-only applications.
      "codex-app"
      "chatgpt"
      "claude"
      "mos"
      "osaurus"
      "termius"

      # Shared GUI intent, installed by the host package manager on macOS.
      "font-jetbrains-mono-nerd-font"
      "zed"
      "tabby"
      "sublime-text"
      "cursor"
      "visual-studio-code"
      "vlc"
      "google-chrome"
      "kitty"
      "hyper"
      "godot"
    ];
    masApps = {
      "KeepSolid VPN Unlimited" = 694633015;
      "Xcode" = 497799835;
    };
  };

  # ProxyBridge is distributed as an upstream signed v3.2.0 package rather
  # than a stable Homebrew cask. Its reviewed, non-secret defaults live in
  # templates/proxybridge and are not installed by this module. Installing the
  # package and approving its network extension remains a deliberate one-time
  # operator action documented in docs/nix-architecture.md.
}
