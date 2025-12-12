# src/lib/users.nix
# SSOT for user/group definitions across all targets

{
  # uid 1000 reserved for dynamic host user (created by cloud-init)

  # Admin user with sudo
  kc2admin = {
    uid = 1001;
    gid = 1001;
    name = "kc2admin";
    home = "/home/kc2admin";
    shell = "/bin/bash";
    gecos = "Konductor Admin";
    groups = [ "kc2admin" "wheel" ];
  };

  # Unprivileged user
  kc2 = {
    uid = 1002;
    gid = 1002;
    name = "kc2";
    home = "/home/kc2";
    shell = "/bin/bash";
    gecos = "Konductor User";
    groups = [ "kc2" "kc2admin" ];
  };

  # Group definitions
  groups = {
    kc2admin = { gid = 1001; members = [ "kc2" ]; };
    kc2 = { gid = 1002; members = [ ]; };
    wheel = { gid = 10; members = [ "kc2admin" ]; };
  };
}
