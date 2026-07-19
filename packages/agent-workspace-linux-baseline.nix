{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libxcb,
  libxkbcommon,
  runCommand,
  file,
}:

let
  version = "0.2.1";
  src = fetchurl {
    url = "https://github.com/agent-sh/agent-workspace-linux/releases/download/v${version}/agent-workspace-linux-x86_64-unknown-linux-gnu";
    hash = "sha256-8KADvl4V5Gb2wcWdsO17MVJLbuI83upR7EYHTSFvkVw=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "agent-workspace-linux";
  inherit version src;

  dontUnpack = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libxcb
    libxkbcommon
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/agent-workspace-linux"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Pinned agent-workspace-linux release binary for Synology dev container";
    homepage = "https://github.com/agent-sh/agent-workspace-linux";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceProvenance; [ binaryNativeCode ];
  };

  # Opt-in smoke check (no execution): the binary is a GUI workspace launcher
  # whose `--version`/`--help` surface is unverified, so running it in the
  # sandbox could hang or start a GUI. Instead assert the shipped artifact is an
  # executable x86-64 ELF. This catches artifact/architecture drift without
  # claiming to prove the binary's exact CPU feature floor.
  passthru.tests.smoke =
    runCommand "${finalAttrs.pname}-smoke"
      {
        nativeBuildInputs = [ file ];
        meta.platforms = [ "x86_64-linux" ];
      }
      ''
        bin="${finalAttrs.finalPackage}/bin/agent-workspace-linux"
        test -x "$bin" || { echo "not executable: $bin" >&2; exit 1; }
        file "$bin" > "$out"
        grep -q "ELF 64-bit LSB.*x86-64" "$out" \
          || { echo "unexpected arch (expected x86-64 ELF):" >&2; cat "$out" >&2; exit 1; }
      '';
})
