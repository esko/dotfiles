{
  lib,
  runCommand,
  buildEnv,
  writeShellApplication,
  coreutils,
  bashInteractive,
  cacert,
  glibc,
  pi-coding-agent,
  mosh,
  eternal-terminal,
  tsshd,
  flow-control,
  homeConfiguration,
  herdrAgent,
  codexAgent,
  antigravityCli,
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

  runtime = buildEnv {
    name = "synology-dev-environment";
    paths = [
      homeConfiguration.config.home.path
      bashInteractive
      coreutils
      pi-coding-agent
      herdrAgent
      mosh
      eternal-terminal
      tsshd
      codexAgent
      antigravityCli
      opencodeBaseline
      hunkBaseline
      flow-control
      entrypoint
    ];
    pathsToLink = [
      "/bin"
      "/share"
    ];
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
  ln -s ${coreutils}/bin/env "$out/usr/bin/env"
  ln -s ${cacert}/etc/ssl/certs/ca-bundle.crt "$out/etc/ssl/certs/ca-bundle.crt"

  cp -a ${homeConfiguration.config."home-files"}/. "$out/home/${username}/"
  chmod u+w "$out/home/${username}"
  chmod u+w "$out/home/${username}/.local"
  mkdir -p \
    "$out/home/${username}/.cache" \
    "$out/home/${username}/.codex" \
    "$out/home/${username}/.config" \
    "$out/home/${username}/.gemini" \
    "$out/home/${username}/.local/share" \
    "$out/home/${username}/.local/state" \
    "$out/home/${username}/.pi"

  cat > "$out/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
esko:x:${toString uid}:${toString gid}:Esko:${homeDirectory}:/bin/zsh
EOF

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
  test "$(readlink -f "$out/bin/herdr")" = "${herdrAgent}/bin/herdr"
  test -x "$out/bin/opencode"
  test -x "$out/bin/hunk"
  test -x "$out/bin/yazi"
  test -x "$out/bin/flow"
  test -x "$out/bin/mosh-server"
  test -x "$out/bin/etserver"
  test -x "$out/bin/tsshd"
  test -x "$out/bin/agy"
  test -x "$out/bin/codex"
  test -x "$out/bin/bun"
  test -x "$out/lib64/ld-linux-x86-64.so.2"
  test ! -e "$out/home/${username}/.ssh/id_ed25519"
''
