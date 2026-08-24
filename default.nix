{
  lib,
  stdenv,
  swift,
  swiftpm,
  swiftpm2nix,
  llvm,
}:

let
  # swiftpm2nix vendors the SwiftPM dependencies (TOMLDecoder) so the build runs
  # offline in the nix sandbox. Regenerate ./nix after changing deps:
  #   swift package resolve && nix run nixpkgs#swiftpm2nix
  generated = swiftpm2nix.helpers ./nix;
  # Written by the release (see scripts/build-release.nu), so the store path and
  # the bundle report the same version the release published.
  version = lib.fileContents ./VERSION;
in
stdenv.mkDerivation {
  pname = "clawd-back";
  inherit version;

  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        base = baseNameOf path;
      in
      base != ".build" && base != ".git" && base != "result";
  };

  # swift for the compiler/swiftpm; llvm supplies dsymutil (release builds
  # generate a dSYM and the nix cctools wrapper doesn't ship dsymutil).
  nativeBuildInputs = [
    swift
    swiftpm
    llvm
  ];

  # Symlink the pre-fetched dependency checkouts into .build so swift build
  # doesn't hit the network.
  configurePhase = ''
    runHook preConfigure
    ${generated.configure}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    swift build -c release --disable-sandbox
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    app="$out/Applications/ClawdBack.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp .build/release/clawd-back "$app/Contents/MacOS/"

    # Whole Resources tree, then relocate Info.plist to Contents/ and drop the
    # signing-only entitlements. Wildcarded so new assets ship without edits.
    cp -R Resources/. "$app/Contents/Resources/"
    mv "$app/Contents/Resources/Info.plist" "$app/Contents/"
    rm -f "$app/Contents/Resources/entitlements.plist"

    # The tree carries a placeholder version, so stamp the real one in.
    substituteInPlace "$app/Contents/Info.plist" \
      --replace-fail 0.0.0-dev "${version}"

    # Every terminal's AppleScripts, preserving their per-terminal subdir so
    # bundledResource("<Term>/<script>") resolves. Wildcarded, not enumerated.
    find Sources -name '*.applescript' | while read -r f; do
      rel="''${f#Sources/}"
      mkdir -p "$app/Contents/Resources/$(dirname "$rel")"
      cp "$f" "$app/Contents/Resources/$rel"
    done

    cp -R hooks "$app/Contents/Resources/"
    chmod +x "$app/Contents/Resources/hooks/"*/*
    runHook postInstall
  '';

  meta = {
    description = "macOS notifier that returns you to the Zellij pane Claude Code runs in";
    platforms = lib.platforms.darwin;
    mainProgram = "clawd-back";
  };
}
