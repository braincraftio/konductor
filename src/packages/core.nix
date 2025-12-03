# src/packages/core.nix
# Minimal Unix utilities - essential for any environment

{ pkgs }:

{
  packages = with pkgs; [
    coreutils # ls, cat, mkdir, cp, mv, rm, etc.
    bashInteractive # Interactive shell with readline
    findutils # find, xargs
    gnugrep # grep
    gnused # sed
    gawk # awk
    gnutar # tar
    gzip # gzip, gunzip
    xz # xz compression
    which # which command
    less # pager
    ncurses # terminal handling, clear, tput
    file # file type detection
    procps # ps, top, pgrep, pkill
  ];

  shellHook = "";
  env = { };
}
