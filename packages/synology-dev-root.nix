{
  lib,
  runCommand,
  buildEnv,
  writeShellApplication,
  coreutils,
  bashInteractive,
  cacert,
  glibc,
  fail2ban,
  iptables,
  ipset,
  agentWorkspaceLinux,
  synologyDevGui,
  eternal-terminal,
  openssh,
  tailscale,
  tsshd,
  flow-control,
  homeConfiguration,
  reasonixAgent,
  hunkBaseline,
  opencodeBaseline,
}:

let
  uid = 1026;
  gid = 100;
  username = "esko";
  homeDirectory = "/home/${username}";

  entrypoint = writeShellApplication {
    name = "synology-dev-entrypoint";
    runtimeInputs = [ coreutils ];
    text = builtins.readFile ../scripts/synology-dev-entrypoint.sh;
  };

  startTailscale = writeShellApplication {
    name = "synology-dev-start-tailscale";
    runtimeInputs = [ coreutils tailscale ];
    text = builtins.readFile ../scripts/synology-dev-start-tailscale.sh;
  };

  startSshd = writeShellApplication {
    name = "synology-dev-start-sshd";
    runtimeInputs = [
      coreutils
      fail2ban
      iptables
      openssh
    ];
    text = builtins.readFile ../scripts/synology-dev-start-sshd.sh;
  };

  startServices = writeShellApplication {
    name = "synology-dev-start-services";
    runtimeInputs = [ coreutils startTailscale startSshd ];
    text = builtins.readFile ../scripts/synology-dev-start-services.sh;
  };

  # home.path already includes shared CLI/agent packages (mosh, tailscale,
  # pi, codex, grok, agy, herdr, …). Only add image-only tools here.
  runtime = buildEnv {
    name = "synology-dev-environment";
    paths = [
      homeConfiguration.config.home.path
      bashInteractive
      coreutils
      fail2ban
      iptables
      ipset
      agentWorkspaceLinux
      synologyDevGui
      reasonixAgent
      eternal-terminal
      tsshd
      opencodeBaseline
      hunkBaseline
      flow-control
      entrypoint
      startTailscale
      startSshd
      startServices
    ];
    pathsToLink = [
      "/bin"
      "/share"
    ];
    # home.path and image helpers can still share common store paths.
    ignoreCollisions = true;
  };
in
runCommand "synology-dev-root" { } ''
  mkdir -p \
    "$out/bin" \
    "$out/etc/ssl/certs" \
    "$out/home/${username}" \
    "$out/tmp" \
    "$out/usr/bin" \
    "$out/workspace"

  mkdir -p "$out/lib64"
  ln -s ${glibc}/lib/ld-linux-x86-64.so.2 "$out/lib64/ld-linux-x86-64.so.2"

  cp -a ${runtime}/bin/. "$out/bin/"
  chmod -R u+w "$out/bin"
  ln -s ${coreutils}/bin/env "$out/usr/bin/env"
  ln -s ${cacert}/etc/ssl/certs/ca-bundle.crt "$out/etc/ssl/certs/ca-bundle.crt"

  cp -a ${fail2ban}/etc/fail2ban/. "$out/etc/fail2ban/"
  chmod -R u+w "$out/etc/fail2ban"
  install -Dm644 ${../config/synology-dev/fail2ban.local} "$out/etc/fail2ban/fail2ban.local"
  install -Dm644 ${../config/synology-dev/paths-synology-dev.conf} "$out/etc/fail2ban/paths-synology-dev.conf"
  mkdir -p "$out/var/lib/fail2ban" "$out/var/run/fail2ban"
  install -Dm755 ${../scripts/synology-dev-workspace-novnc.sh} "$out/bin/synology-dev-workspace-novnc"

  cp -a ${homeConfiguration.config."home-files"}/. "$out/home/${username}/"
  chmod u+w "$out/home/${username}"
  chmod u+w "$out/home/${username}/.local"
  mkdir -p \
    "$out/home/${username}/.cache" \
    "$out/home/${username}/.codex" \
    "$out/home/${username}/.config" \
    "$out/home/${username}/.gemini" \
    "$out/home/${username}/.reasonix" \
    "$out/home/${username}/.local/share" \
    "$out/home/${username}/.local/state" \
    "$out/home/${username}/.pi"

  cat > "$out/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
sshd:x:74:74:Privilege-separated SSH:/var/empty/sshd:/sbin/nologin
esko:x:${toString uid}:${toString gid}:Esko:${homeDirectory}:/bin/zsh
EOF

  mkdir -p "$out/var/empty/sshd"
  chmod 711 "$out/var/empty/sshd"

  cat > "$out/etc/group" <<'EOF'
root:x:0:
users:x:${toString gid}:esko
EOF

  cat > "$out/etc/nsswitch.conf" <<'EOF'
passwd: files
group: files
hosts: files dns
networks: files dns
EOF

  cat > "$out/etc/shells" <<'EOF'
/bin/sh
/bin/bash
/bin/zsh
EOF

  chmod 1777 "$out/tmp"

  # Keep the declared identity easy to inspect from tests and deployment docs.
  cat > "$out/etc/synology-dev-release" <<'EOF'
NAME=dotfiles-synology-dev
ARCH=x86_64-linux
USER=${username}
UID=${toString uid}
GID=${toString gid}
EOF

  test -x "$out/bin/pi"
  test -x "$out/bin/herdr"
  test -x "$out/bin/reasonix"
  test -x "$out/bin/opencode"
  test -x "$out/bin/hunk"
  test -x "$out/bin/yazi"
  test -x "$out/bin/flow"
  test -x "$out/bin/mosh-server"
  test -x "$out/bin/etserver"
  test -x "$out/bin/tailscale"
  test -x "$out/bin/tailscaled"
  test -x "$out/bin/synology-dev-start-tailscale"
  test -x "$out/bin/synology-dev-start-services"
  test -x "$out/bin/tsshd"
  test -x "$out/bin/agy"
  test -x "$out/bin/grok"
  test -x "$out/bin/codex"
  test -x "$out/bin/bun"
  test -x "$out/bin/fail2ban-server"
  test -x "$out/bin/iptables"
  test -x "$out/bin/agent-workspace-linux"
  test -x "$out/bin/Xvfb"
  test -x "$out/bin/chromium"
  test -x "$out/bin/xdotool"
  test -f "$out/etc/fail2ban/filter.d/sshd.conf"
  test -f "$out/etc/fail2ban/paths-synology-dev.conf"
  test -x "$out/lib64/ld-linux-x86-64.so.2"
  test ! -e "$out/home/${username}/.ssh/id_ed25519"
''
