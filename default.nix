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
in
stdenv.mkDerivation {
  pname = "claude-zellij-whip";
  version = "1.0.0";

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
    app="$out/Applications/ClaudeZellijWhip.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp .build/release/claude-zellij-whip "$app/Contents/MacOS/"
    cp Resources/Info.plist "$app/Contents/"
    cp Resources/AppIcon.icns "$app/Contents/Resources/"
    runHook postInstall
  '';

  meta = {
    description = "macOS notifier that returns you to the Zellij pane Claude Code runs in";
    platforms = lib.platforms.darwin;
    mainProgram = "claude-zellij-whip";
  };
}
