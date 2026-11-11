# src/harness/opencode/tui.nix
# Native V2 cli.json defaults; terminal presentation is independent of server config.
#
# Consumed by default.nix via pkgs.formats.json.

_:

{
  "$schema" = "https://opencode.ai/v2/cli.json";
  theme = {
    name = "catppuccin-frappe";
    mode = "dark";
  };
  session = {
    grouping = "none";
    verbosity = "high";
    thinking = "show";
    scrollbar = false;
    tps = true;
    permissions = "prompt";
    new_location = "launch";
    image_preview = true;
    markdown = "rendered";
    sidebar = "hide";
  };
  mini = {
    thinking = "show";
    tools = "show";
    shell_output = "show";
    turn_summary = "show";
    footer = "show";
    replay = true;
  };
  attention = {
    notifications = true;
    sound = false;
    volume = 0.4;
  };
  terminal = {
    title = true;
    copy = "manual";
  };
  prompt = {
    editor = true;
    paste = "full";
    image_preview = true;
  };
  diffs = {
    source = "branch";
    wrap = "word";
    tree = true;
    single = false;
    view = "auto";
  };
  tabs = {
    mode = "auto";
    scope = "cwd";
    layout = "horizontal";
    indicators = "status";
  };
  mouse = true;
  experimental = {
    terminal-left = true;
    vim-pane-navigation = true;
  };
}
