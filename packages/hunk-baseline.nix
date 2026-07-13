{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bunBaseline,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hunkdiff-baseline";
  version = "0.17.0";

  hunkSource = fetchurl {
    url = "https://registry.npmjs.org/hunkdiff/-/hunkdiff-${finalAttrs.version}.tgz";
    hash = "sha256-NLX66TgpsZzTwsgB8NPF1WlQ4VK56e7lsnm5j6GksOg=";
  };
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/hunkdiff"
    tar -xzf "$hunkSource" --strip-components=1 -C "$out/lib/hunkdiff"

    makeWrapper "${bunBaseline}/bin/bun" "$out/bin/hunk" \
      --add-flags "$out/lib/hunkdiff/dist/npm/main.js"
    ln -s hunk "$out/bin/hunkdiff"

    runHook postInstall
  '';

  meta = {
    description = "Hunk diff viewer using Bun's baseline x86_64 runtime";
    homepage = "https://github.com/modem-dev/hunk";
    license = lib.licenses.mit;
    mainProgram = "hunk";
    platforms = [ "x86_64-linux" ];
  };
})
