# src/packages/system.nix
# System integration packages (NSS, PAM, etc.)

{ pkgs, lib }:

{
  packages = with pkgs; [
    iana-etc # /etc/protocols and /etc/services
    getent # NSS lookups (getent passwd, etc.)
    rsync # File sync with permission preservation
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    gosu # Privilege de-escalation for containers (Linux only)
    su # su command for user switching (Linux only)
    linux-pam # PAM libraries required for sudo (Linux only)
  ];

  shellHook = "";
  env = { };
}
