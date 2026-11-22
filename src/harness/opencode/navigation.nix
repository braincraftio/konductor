{
  pkgs,
  lib ? pkgs.lib,
}:

pkgs.writeShellApplication {
  name = "konductor-pane-navigation";
  text = ''
    exec ${lib.getExe pkgs.python3} -I -S ${./navigation.py} --tmux ${lib.getExe pkgs.tmux} "$@"
  '';
}
