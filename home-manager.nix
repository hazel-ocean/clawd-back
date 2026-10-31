self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.clawd-back;
  hookNames = [
    "capture"
    "notify"
    "cleanup"
  ];
in
{
  options.programs.clawd-back = {
    enable = lib.mkEnableOption "ClawdBack, the notifier that returns you to Claude Code";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "clawd-back.packages.\${system}.default";
      description = "The ClawdBack package.";
    };

    hooks = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "nushell"
          "bash"
        ]
      );
      default = null;
      example = "nushell";
      description = ''
        The hook set to link at `~/.claude/hooks/{capture,notify,cleanup}`.
        Point the Claude Code hook commands at those paths. `null` links none.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          (lib.hm.assertions.assertPlatform "programs.clawd-back" pkgs lib.platforms.darwin)
        ];

        # A click relaunches the app by bundle id, so LaunchServices needs a
        # real copy at a stable path; a store path changes on every rebuild.
        home.activation.installClawdBack = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          dest="$HOME/Applications/ClawdBack.app"
          run rm -rf "$dest"
          run mkdir -p "$HOME/Applications"
          run cp -RL ${cfg.package}/Applications/ClawdBack.app "$dest"
          run chmod -R u+w "$dest"
          run /usr/bin/codesign --force --sign - "$dest"
          run /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$dest"
        '';
      }
      (lib.mkIf (cfg.hooks != null) {
        home.file = lib.listToAttrs (
          map (
            name: lib.nameValuePair ".claude/hooks/${name}" { source = cfg.package.hooks.${cfg.hooks}.${name}; }
          ) hookNames
        );
      })
    ]
  );
}
