{
  lib,
  fetchurl,
  appimageTools,
  unzip,
  runCommand,
  stdenvNoCC,
  wrapGAppsHook3,
  gdk-pixbuf,
  librsvg,
  shared-mime-info,
  adwaita-icon-theme,
  file,
}:

let
  # Keep the binary name distinct from nixpkgs inkscape (1.4.x) so both can
  # live on PATH: `inkscape` (stable) and `inkscape-beta` (1.5-dev).
  pname = "inkscape-beta";
  # Inkscape 1.5 development AppImage from GitLab CI master @ e76072a (2026-07-14).
  # Upstream does not publish a stable 1.5 tarball yet; pin a successful
  # appimage:linux job and bump intentionally when refreshing.
  version = "1.5.0-dev.20260714.e76072a";
  jobId = "15326770658";

  # GTK/pixbuf/mime/icon data that Inkscape needs at runtime. Putting these
  # only on the user profile is not enough for an extracted AppImage; they must
  # be visible inside the FHS env and on the final wrapper's environment.
  gtkRuntimePkgs =
    pkgs: with pkgs; [
      gdk-pixbuf
      librsvg
      shared-mime-info
      adwaita-icon-theme
    ];

  srcZip = fetchurl {
    url = "https://gitlab.com/api/v4/projects/inkscape%2Finkscape/jobs/${jobId}/artifacts";
    hash = "sha256-ZL/q0l+zCnJDDiP8RAPO7RMFxUyu6mVYwtOK8SZXH7M=";
  };

  src =
    runCommand "${pname}-${version}.AppImage"
      {
        nativeBuildInputs = [ unzip ];
        inherit srcZip;
      }
      ''
        unzip -j "$srcZip" '*.AppImage'
        mv Inkscape-*.AppImage "$out"
      '';

  appimage = appimageTools.wrapType2 {
    inherit pname version src;

    # Host the GTK stack inside the AppImage FHS environment.
    extraPkgs = gtkRuntimePkgs;

    meta = with lib; {
      description = "Inkscape 1.5 development AppImage (pinned GitLab CI build)";
      homepage = "https://inkscape.org/release/inkscape-dev/";
      changelog = "https://wiki.inkscape.org/wiki/Release_notes/1.5";
      license = licenses.gpl3Plus;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with sourceProvenance; [ binaryNativeCode ];
      mainProgram = "inkscape-beta";
    };
  };
in
# Outer wrapGAppsHook3 sets GDK_PIXBUF_MODULE_FILE and XDG_DATA_DIRS on the
# final executable; extraPkgs alone does not always export those variables.
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ wrapGAppsHook3 ];
  buildInputs = [
    gdk-pixbuf
    librsvg
    shared-mime-info
    adwaita-icon-theme
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    ln -s ${lib.getExe appimage} "$out/bin/${pname}"
    runHook postInstall
  '';

  meta = appimage.meta;

  # Opt-in structural smoke (no execution): running the wrapped AppImage's
  # `--version` inside the Nix build sandbox is not reliable because the
  # appimageTools wrapper sets up an FHS env via bwrap, which a sandboxed
  # builder may not permit. Instead assert the shipped launcher is executable
  # and the underlying AppImage payload is an x86-64 ELF. This guards against
  # artifact/architecture drift but does not prove an exact CPU feature floor.
  passthru.tests.smoke =
    runCommand "${pname}-smoke"
      {
        nativeBuildInputs = [ file ];
        meta.platforms = [ "x86_64-linux" ];
      }
      ''
        bin="${lib.getExe appimage}"
        test -x "$bin" || { echo "inkscape-beta launcher not executable: $bin" >&2; exit 1; }
        file "${src}" > "$out"
        grep -q "ELF 64-bit LSB.*x86-64" "$out" \
          || { echo "AppImage payload is not an x86-64 ELF:" >&2; cat "$out" >&2; exit 1; }
      '';
}
