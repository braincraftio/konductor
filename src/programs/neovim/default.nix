# src/programs/neovim/default.nix
# Konductor Neovim - nixvim-native, snacks.nvim powered
#
# Flat architecture (v2):
#   options.nix     - vim.opt settings
#   autocmds.nix    - autocommands
#   plugins.nix     - ALL plugin configurations
#   keymaps.nix     - ALL keybindings
#   extraConfig.nix - raw Lua (minimal)
#
# Design principles:
#   - Native first: use nixvim plugins.* for everything
#   - Snacks consolidation: picker, explorer, terminal, dashboard, etc.
#   - LazyVim conventions: keybinding patterns and UX

{ pkgs, lib, inputs }:

let
  nixvimPkgs = inputs.nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Import configuration modules
  pluginsCfg = import ./plugins.nix { inherit pkgs lib; };
  keymapsCfg = import ./keymaps.nix { inherit lib; };
  optionsCfg = import ./options.nix { inherit pkgs; };
  autocmdsCfg = import ./autocmds.nix { };
  extraConfigCfg = import ./extraConfig.nix { };

  # Build nixvim configuration
  nixvimConfig = nixvimPkgs.makeNixvim {
    # Colorscheme
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "macchiato";
        integrations = {
          cmp = true;
          gitsigns = true;
          treesitter = true;
          which_key = true;
          mini = { enabled = true; };
          snacks = true;
        };
      };
    };

    # Core settings
    inherit (optionsCfg) opts globals;
    inherit (autocmdsCfg) autoCmd;
    inherit (keymapsCfg) keymaps;

    # All plugins via nixvim native options
    inherit (pluginsCfg) plugins;

    # Extra plugins only for what nixvim doesn't support
    inherit (pluginsCfg) extraPlugins;

    # Extra Lua packages for plugin dependencies
    # luasql-sqlite3: Required for snacks.picker frecency feature
    extraLuaPackages = luaPkgs: with luaPkgs; [
      luasql-sqlite3
    ];

    # Lua configuration
    inherit (extraConfigCfg) extraConfigLua extraConfigLuaPre;

    # Performance optimizations
    performance = {
      byteCompileLua = {
        enable = true;
        initLua = true;
        configs = true;
        plugins = true;
        nvimRuntime = false;
      };
      combinePlugins.enable = false;
    };

    # Clipboard support
    clipboard.providers.wl-copy.enable = true;

    # Create vi/vim aliases
    viAlias = true;
    vimAlias = true;
  };

  # Create vimdiff wrapper script (vimdiffAlias only works in Home Manager)
  vimdiffWrapper = pkgs.writeShellScriptBin "vimdiff" ''
    exec ${nixvimConfig}/bin/nvim -d "$@"
  '';

in
{
  packages = [ nixvimConfig vimdiffWrapper ];
  shellHook = "";
  env = { };
}
