{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.zellij;
  yamlFormat = pkgs.formats.yaml { };
  zellijCmd = getExe cfg.package;

in {
  meta.maintainers = [ hm.maintainers.mainrs ];

  options.programs.zellij = {
    enable = mkEnableOption "zellij";

    package = mkOption {
      type = types.package;
      default = pkgs.zellij;
      defaultText = literalExpression "pkgs.zellij";
      description = ''
        The zellij package to install.
      '';
    };

    settings = mkOption {
      type = yamlFormat.type;
      default = { };
      example = literalExpression ''
        {
          theme = "custom";
          themes.custom.fg = "#ffffff";
        }
      '';
      description = ''
        Configuration written to
        {file}`$XDG_CONFIG_HOME/zellij/config.yaml`.

        See <https://zellij.dev/documentation> for the full
        list of options.
      '';
    };

    layouts = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = literalExpression ''
        {
          default = {
            id = "layout";
            children = [
              {
                id = "pane";
                props = { split_direction = "vertical"; };
                children = [
                  {
                    id = "pane";
                  }
                  {
                    id = "pane";
                    props = { split_direction = "horizontal"; };
                    children = [
                      { id = "pane"; }
                      { id = "pane"; }
                    ];
                  }
                ];
              }
            ];
          };
        }
      '';
      description = ''
        Set of named layouts written to
        {file}`$XDG_CONFIG_HOME/zellij/layouts/*.kdl`.

        See <https://zellij.dev/documentation/layouts> for instructions on
        composing custom layouts and referencing them in the zellij config.
      '';
    };

    enableBashIntegration = mkEnableOption "Bash integration" // {
      default = false;
    };

    enableZshIntegration = mkEnableOption "Zsh integration" // {
      default = false;
    };

    enableFishIntegration = mkEnableOption "Fish integration" // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile = {
      # Zellij switched from yaml to KDL in version 0.32.0:
      # https://github.com/zellij-org/zellij/releases/tag/v0.32.0
      "zellij/config.yaml" = mkIf
        (cfg.settings != { } && (versionOlder cfg.package.version "0.32.0")) {
          source = yamlFormat.generate "zellij.yaml" cfg.settings;
        };

      "zellij/config.kdl" = mkIf
        (cfg.settings != { } && (versionAtLeast cfg.package.version "0.32.0")) {
          text = lib.hm.generators.toKDL { } cfg.settings;
        };
      #"zellij/layouts/default.kdl" = {
      #  text = lib.hm.generators.toKDL { } cfg.layouts.default;
      #};
    }
    # Spread "layouts" set into configFile attrs/entries
    // (lib.attrsets.concatMapAttrs
      (name: value: {
        "zellij/layouts/${name}.kdl" = {
          text = lib.hm.generators.toKDL { } value;
        };
      })
      cfg.layouts
    );


    programs.bash.initExtra = mkIf cfg.enableBashIntegration (mkOrder 200 ''
      eval "$(${zellijCmd} setup --generate-auto-start bash)"
    '');

    programs.zsh.initExtra = mkIf cfg.enableZshIntegration (mkOrder 200 ''
      eval "$(${zellijCmd} setup --generate-auto-start zsh)"
    '');

    programs.fish.interactiveShellInit = mkIf cfg.enableFishIntegration
      (mkOrder 200 ''
        eval (${zellijCmd} setup --generate-auto-start fish | string collect)
      '');
  };
}
