{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libxcb,
  libxkbcommon,
}:

let
  version = "0.2.1";
  src = fetchurl {
    url = "https://github.com/agent-sh/agent-workspace-linux/releases/download/v${version}/agent-workspace-linux-x86_64-unknown-linux-gnu";
    hash = "sha256-8KADvl4V5Gb2wcWdsO17MVJLbuI83upR7EYHTSFvkVw=";
  };
in
stdenv.mkDerivation {
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
}
