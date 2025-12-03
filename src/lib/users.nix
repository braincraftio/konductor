# src/lib/users.nix
# SSOT for user/group definitions across all targets

{
  # Primary unprivileged user
  kc2 = {
    uid = 1000;
    gid = 1000;
    name = "kc2";
    home = "/home/kc2";
    shell = "/bin/bash";
    gecos = "Konductor User";
    groups = [ "kc2" ];
  };

  # Admin user with sudo
  kc2admin = {
    uid = 1001;
    gid = 1001;
    name = "kc2admin";
    home = "/home/kc2admin";
    shell = "/bin/bash";
    gecos = "Konductor Admin";
    groups = [ "kc2admin" "kc2" "wheel" ];
  };

  # Group definitions
  groups = {
    kc2 = { gid = 1000; members = [ "kc2admin" ]; };
    kc2admin = { gid = 1001; members = [ ]; };
    wheel = { gid = 10; members = [ "kc2admin" ]; };
  };
}
