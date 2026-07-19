# Static check derivations for the dotfiles flake.
#
# Each derivation copies the filtered flake source (`self`) into the build
# sandbox and runs one of the existing tests/*.sh or scripts/check-*.sh
# scripts against it. The scripts are NOT re-implemented here — they live in
# the working tree and remain the single source of truth. No derivation
# recursively invokes `nix`.
#
# `nix` is deliberately excluded from runtimeInputs so that
# tests/secrets-static.sh skips its optional `nix eval` block (the copied
# source is not a flake ref inside the sandbox and would otherwise need
# network access). tests/shell-static.sh similarly skips its optional
# `nix-instantiate --parse` block; the grep-based structural checks that
# matter still run.

{
  pkgs,
  self,
  system,
}:

let
  # Tools shared by every static check script. ripgrep covers the `rg` calls,
  # jq covers JSON validation in darwin-static, and the GNU coreutils/findutils
  # pair satisfies `tr`, `test`, `grep`, `awk`, `sed` references.
  baseInputs = with pkgs; [
    ripgrep
    jq
    bash
    coreutils
    findutils
    gnugrep
    gawk
    gnused
  ];

  # Run a static check script against a copy of the flake source. The scripts
  # resolve repo_root themselves via BASH_SOURCE, so we invoke them by
  # relative path after cd-ing into the copied tree.
  mkStaticCheck =
    name: scriptPath: extraInputs:
    pkgs.runCommand "check-${name}"
      {
        nativeBuildInputs = baseInputs ++ extraInputs;
        src = self;
      }
      ''
        cp -r "$src" source
        chmod -R u+w source
        cd source
        bash ${scriptPath}
        touch "$out"
      '';

  # check-llm-context-safe.sh relies on `git ls-files` and `git grep`, which
  # require a real git index. Initialize a throwaway repo from the
  # already-filtered flake source so only tracked files are scanned. A
  # minimal user identity is configured so `git add` does not refuse to run.
  mkGitStaticCheck =
    name: scriptPath: extraInputs:
    pkgs.runCommand "check-${name}"
      {
        nativeBuildInputs = baseInputs ++ [ pkgs.git ] ++ extraInputs;
        src = self;
      }
      ''
        export HOME="$NIX_BUILD_TOP/home"
        mkdir -p "$HOME"
        git config --global user.email "nix-check@localhost"
        git config --global user.name "nix-check"
        cp -r "$src" source
        chmod -R u+w source
        cd source
        git init -q
        git add -A
        bash ${scriptPath}
        touch "$out"
      '';

  commonChecks = {
    nix-format =
      pkgs.runCommand "check-nix-format"
        {
          nativeBuildInputs = [
            pkgs.findutils
            pkgs.nixfmt
          ];
          src = self;
        }
        ''
          cp -r "$src" source
          find source -name '*.nix' -print0 | xargs -0 nixfmt --check
          touch "$out"
        '';
    secrets-static = mkStaticCheck "secrets-static" "tests/secrets-static.sh" [ ];
    shell-static = mkStaticCheck "shell-static" "tests/shell-static.sh" [ pkgs.zsh ];
    update-static = mkStaticCheck "update-static" "tests/update-static.sh" [ ];
    llm-context-safe = mkGitStaticCheck "llm-context-safe" "scripts/check-llm-context-safe.sh" [ ];
  };

in
commonChecks
// (
  if system == "x86_64-linux" then
    {
      install-node-tools = mkStaticCheck "install-node-tools" "tests/install-node-tools.sh" [ ];
      linux-static = mkStaticCheck "linux-static" "tests/linux-static.sh" [ ];
      synology-dev-static = mkStaticCheck "synology-dev-static" "tests/synology-dev-static.sh" [ ];
    }
  else if system == "aarch64-darwin" then
    { darwin-static = mkStaticCheck "darwin-static" "tests/darwin-static.sh" [ ]; }
  else
    { }
)
