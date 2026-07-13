{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "bun-baseline";
  version = "1.3.14";

  src = fetchurl {
    url = "https://registry.npmjs.org/@oven/bun-linux-x64-baseline/-/bun-linux-x64-baseline-${finalAttrs.version}.tgz";
    hash = "sha256-HVirMyv4GjHvPVnQ3a8tYOiIm32p5qQXYkkr9WdaK+U=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$TMPDIR/bun-baseline"
    tar -xzf "$src" --strip-components=1 -C "$TMPDIR/bun-baseline"
    install -Dm755 "$TMPDIR/bun-baseline/bin/bun" "$out/bin/bun"
    ln -s bun "$out/bin/bunx"

    runHook postInstall
  '';

  meta = {
    description = "Bun runtime built for baseline x86_64 CPUs";
    homepage = "https://bun.com";
    license = lib.licenses.mit;
    mainProgram = "bun";
    platforms = [ "x86_64-linux" ];
  };
})
