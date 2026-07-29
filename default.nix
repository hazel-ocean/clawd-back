{
  lib,
  stdenv,
  swift,
  swiftpm,
  llvm,
}:

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
