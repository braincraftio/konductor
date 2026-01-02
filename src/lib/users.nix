# src/lib/users.nix
# SSOT for user/group definitions across all targets
#
# Shared Access Model:
#   - kc2 group (GID 1001) is the shared group for all users
#   - All users are members of kc2 group for shared directory access
#   - UID 1000 reserved for dynamic cloud-init user creation
#   - Shared directories use setgid (2775) so new files inherit kc2 group

{
  # uid 1000 reserved for dynamic host user (created by cloud-init)

  # Unprivileged user - primary group for shared access
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
    groups = [ "kc2admin" "kc2" "wheel" ];
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
    groups = [ "runner" "kc2" "docker" "libvirtd" "kvm" ];
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
    groups = [ "forgejo" "kc2" "docker" ];
  };

  # Group definitions
  # kc2 is the shared group - all users are members for shared directory access
  groups = {
    kc2 = { gid = 1001; members = [ "kc2admin" "runner" "forgejo" ]; };
    kc2admin = { gid = 1002; members = [ ]; };
    runner = { gid = 1003; members = [ ]; };
    forgejo = { gid = 1004; members = [ ]; };
    wheel = { gid = 10; members = [ "kc2admin" ]; };
  };
}
