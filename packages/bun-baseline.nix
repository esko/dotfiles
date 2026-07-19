{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
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
  nativeInstallCheckInputs = [ versionCheckHook ];

  # `bun --version` is a no-network, no-GUI print that exits 0, so it is safe
  # to gate the build. The baseline runtime itself is reliable under QEMU TCG;
  # only Bun-compiled payloads (e.g. opencodeBaseline) are not, and those are
  # exercised on the real DS918+ instead.
  doInstallCheck = true;

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
