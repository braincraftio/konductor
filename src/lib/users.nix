# src/lib/users.nix
# SSOT for user/group definitions across all targets

{
  # uid 1000 reserved for dynamic host user (created by cloud-init)

  # Unprivileged user
  kc2 = {
    uid = 1001;
    gid = 1001;
    name = "kc2";
    home = "/home/kc2";
    shell = "/bin/bash";
    gecos = "Konductor User";
    groups = [ "kc2" ];
  };

  # Admin user with sudo
  kc2admin = {
    uid = 1002;
    gid = 1002;
    name = "kc2admin";
    home = "/home/kc2admin";
    shell = "/bin/bash";
    gecos = "Konductor Admin";
    groups = [ "kc2admin" "wheel" ];
  };

  # CI/CD runner user (for forgejo-runner agents)
  # Executes Forgejo Actions workflows
  runner = {
    uid = 1003;
    gid = 1003;
    name = "runner";
    home = "/home/runner";
    shell = "/bin/bash";
    gecos = "Forgejo Runner";
    groups = [ "runner" "docker" "libvirtd" "kvm" ];
  };

  # Forgejo server user
  # Runs the Forgejo git forge server process
  forgejo = {
    uid = 1004;
    gid = 1004;
    name = "forgejo";
    home = "/home/forgejo";
    shell = "/bin/bash";
    gecos = "Forgejo Server";
    groups = [ "forgejo" "docker" ];
  };

  # Group definitions
  groups = {
    kc2 = { gid = 1001; members = [ ]; };
    kc2admin = { gid = 1002; members = [ "kc2" ]; };
    runner = { gid = 1003; members = [ ]; };
    forgejo = { gid = 1004; members = [ ]; };
    wheel = { gid = 10; members = [ "kc2admin" ]; };
  };
}
