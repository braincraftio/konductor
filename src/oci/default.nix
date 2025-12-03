# src/oci/default.nix
# OCI container build

{ pkgs, lib, nix2container, ... }:

let
  versions = import ../lib/versions.nix;
  users = import ../lib/users.nix;
  env = import ../lib/env.nix;
  shellContent = import ../lib/shell-content.nix { inherit lib; };

  # Import packages from src/packages/
  devshellPackages = import ../packages {
    inherit pkgs lib versions;
  };

  # Nix build users configuration
  nixbld = {
    gid = 30000;
    startUid = 30001;
    count = 32;
  };

  # Generate nixbld user entries for passwd
  nixbldPasswdEntries = lib.concatMapStrings
    (i:
      "nixbld${toString i}:x:${toString (nixbld.startUid + i - 1)}:${toString nixbld.gid}:Nix build user ${toString i}:/var/empty:/sbin/nologin\n"
    )
    (lib.range 1 nixbld.count);

  # Generate nixbld user entries for shadow
  nixbldShadowEntries = lib.concatMapStrings
    (i:
      "nixbld${toString i}:!:1::::::\n"
    )
    (lib.range 1 nixbld.count);

  # System configuration files
  passwdFile = pkgs.writeTextDir "etc/passwd" ''
    root:x:0:0:root:/root:/bin/bash
    nobody:x:65534:65534:Nobody:/nonexistent:/sbin/nologin
    kc2:x:${toString users.kc2.uid}:${toString users.kc2.gid}:${users.kc2.gecos}:${users.kc2.home}:${users.kc2.shell}
    kc2admin:x:${toString users.kc2admin.uid}:${toString users.kc2admin.gid}:${users.kc2admin.gecos}:${users.kc2admin.home}:${users.kc2admin.shell}
    ${nixbldPasswdEntries}'';

  # Generate nixbld group members list
  nixbldMembers = lib.concatStringsSep "," (map (i: "nixbld${toString i}") (lib.range 1 nixbld.count));

  groupFile = pkgs.writeTextDir "etc/group" ''
    root:x:0:
    wheel:x:10:kc2admin
    nobody:x:65534:
    kc2:x:${toString users.kc2.gid}:kc2admin
    kc2admin:x:${toString users.kc2admin.gid}:
    nixbld:x:${toString nixbld.gid}:${nixbldMembers}
  '';

  shadowFile = pkgs.writeTextDir "etc/shadow" ''
    root:!:1::::::
    nobody:!:1::::::
    kc2:!:1::::::
    kc2admin:!:1::::::
    ${nixbldShadowEntries}'';

  gshadowFile = pkgs.writeTextDir "etc/gshadow" ''
    root:x::
    wheel:x::kc2admin
    nobody:x::
    kc2:x::
    kc2admin:x::
    nixbld:x::${nixbldMembers}
  '';

  sudoersFile = pkgs.writeTextDir "etc/sudoers.d/konductor" ''
    # Konductor sudoers configuration
    kc2admin ALL=(ALL:ALL) NOPASSWD: ALL
    %wheel ALL=(ALL:ALL) NOPASSWD: ALL
  '';

  nsswitchFile = pkgs.writeTextDir "etc/nsswitch.conf" ''
    passwd:    files
    group:     files
    shadow:    files
    hosts:     files dns
    networks:  files
    protocols: files
    services:  files
    ethers:    files
    rpc:       files
  '';

  # PAM Configuration
  pamSudo = pkgs.writeTextDir "etc/pam.d/sudo" ''
    auth       sufficient   pam_rootok.so
    auth       sufficient   pam_permit.so
    account    sufficient   pam_permit.so
    session    optional     pam_permit.so
  '';

  pamSu = pkgs.writeTextDir "etc/pam.d/su" ''
    auth       sufficient   pam_rootok.so
    auth       sufficient   pam_permit.so
    account    sufficient   pam_permit.so
    session    optional     pam_permit.so
  '';

  pamOther = pkgs.writeTextDir "etc/pam.d/other" ''
    auth       sufficient   pam_rootok.so
    auth       sufficient   pam_permit.so
    account    sufficient   pam_permit.so
    session    optional     pam_permit.so
  '';

  # Skeleton files using centralized shell content (standalone version with env exports)
  skelFiles = pkgs.runCommand "etc-skel" { } ''
        mkdir -p $out/etc/skel/.config $out/etc/skel/.cache $out/etc/skel/.local/share $out/etc/skel/.local/state $out/etc/skel/.local/bin

        cat > $out/etc/skel/.bashrc <<'EOF'
    ${shellContent.bashrcContentStandalone}
    EOF

        cat > $out/etc/skel/.bash_profile <<'EOF'
    ${shellContent.bashProfileContent}
    EOF

        cat > $out/etc/skel/.inputrc <<'EOF'
    ${shellContent.inputrcContent}
    EOF

        cat > $out/etc/skel/.gitconfig <<'EOF'
    ${shellContent.gitconfigContent}
    EOF

        cat > $out/etc/skel/.config/starship.toml <<'EOF'
    ${shellContent.starshipConfigContent}
    EOF

        chmod 644 $out/etc/skel/.bashrc $out/etc/skel/.bash_profile $out/etc/skel/.inputrc $out/etc/skel/.gitconfig
        chmod 644 $out/etc/skel/.config/starship.toml
  '';

  # Profile script with welcome message
  profileScript = pkgs.writeTextDir "etc/profile.d/konductor.sh" shellContent.welcomeMessageContent;

  # Home directories
  homeDirectories = pkgs.runCommand "home-directories" { } ''
    mkdir -p $out/home/kc2/.config $out/home/kc2/.cache/starship $out/home/kc2/.local/share $out/home/kc2/.local/state $out/home/kc2/.local/bin
    mkdir -p $out/home/kc2admin/.config $out/home/kc2admin/.cache/starship $out/home/kc2admin/.local/share $out/home/kc2admin/.local/state $out/home/kc2admin/.local/bin
    mkdir -p $out/root/.cache/starship

    for user in kc2 kc2admin; do
      cp ${skelFiles}/etc/skel/.bashrc $out/home/$user/
      cp ${skelFiles}/etc/skel/.bash_profile $out/home/$user/
      cp ${skelFiles}/etc/skel/.inputrc $out/home/$user/
      cp ${skelFiles}/etc/skel/.gitconfig $out/home/$user/
      cp ${skelFiles}/etc/skel/.config/starship.toml $out/home/$user/.config/
    done

    cp ${skelFiles}/etc/skel/.bashrc $out/root/
    cp ${skelFiles}/etc/skel/.bash_profile $out/root/

    chmod -R u+rwX,go+rX $out/home/kc2 $out/home/kc2admin $out/root
  '';

  # Standard directories
  standardDirs = pkgs.runCommand "standard-dirs" { } ''
    mkdir -p $out/tmp $out/var/empty
    chmod 1777 $out/tmp
  '';

  # Nix configuration for containers
  nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
    experimental-features = nix-command flakes
    sandbox = false
    filter-syscalls = false
    accept-flake-config = true
    trusted-users = root kc2 kc2admin
    substituters = https://cache.nixos.org https://nix-community.cachix.org
    trusted-substituters = https://cache.nixos.org https://nix-community.cachix.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
  '';

  # Pre-configured flake registry
  nixRegistry = pkgs.writeTextDir "etc/nix/registry.json" (builtins.toJSON {
    version = 2;
    flakes = [
      {
        from = { type = "indirect"; id = "konductor"; };
        to = { type = "github"; owner = "braincraftio"; repo = "konductor"; };
      }
    ];
  });

  # Root filesystem combining all system files
  rootEnv = pkgs.buildEnv {
    name = "konductor-root";
    # Use devshellPackages.default (no languages, no IDE)
    paths = devshellPackages.default ++ [
      passwdFile
      groupFile
      shadowFile
      gshadowFile
      sudoersFile
      nsswitchFile
      pamSudo
      pamSu
      pamOther
      skelFiles
      profileScript
      homeDirectories
      standardDirs
      pkgs.dockerTools.caCertificates
      pkgs.sudo
      pkgs.linux-pam
      # Nix for on-the-fly environment switching
      pkgs.nix
      pkgs.cachix
      nixConf
      nixRegistry
    ];
    pathsToLink = [ "/" ];
  };

  # Permission rules for setuid and file ownership
  permissionRules = [
    {
      path = pkgs.sudo;
      regex = ".*/bin/sudo$";
      mode = "4755";
      uid = 0;
      gid = 0;
    }
    {
      path = shadowFile;
      regex = ".*/etc/shadow$";
      mode = "0640";
      uid = 0;
      gid = 0;
    }
    {
      path = gshadowFile;
      regex = ".*/etc/gshadow$";
      mode = "0640";
      uid = 0;
      gid = 0;
    }
    {
      path = sudoersFile;
      regex = ".*/etc/sudoers.d/konductor$";
      mode = "0440";
      uid = 0;
      gid = 0;
    }
    {
      path = homeDirectories;
      regex = ".*/home/kc2(/.*)?$";
      uid = 1000;
      gid = 1000;
    }
    {
      path = homeDirectories;
      regex = ".*/home/kc2admin(/.*)?$";
      uid = 1001;
      gid = 1001;
    }
    {
      path = homeDirectories;
      regex = ".*/root(/.*)?$";
      uid = 0;
      gid = 0;
    }
  ];

in
{
  # Konductor OCI Image
  image = nix2container.buildImage {
    name = "ghcr.io/braincraftio/konductor";
    tag = "latest";

    perms = permissionRules;
    copyToRoot = [ rootEnv ];

    config = {
      Env = [
        "PATH=/bin"
        "SSL_CERT_FILE=${env.SSL_CERT_FILE}"
        "NIX_SSL_CERT_FILE=${env.NIX_SSL_CERT_FILE}"
        "LANG=${env.LANG}"
        "LC_ALL=${env.LC_ALL}"
        "HOME=/home/kc2"
        "USER=kc2"
        "TERM=${env.TERM}"
        "EDITOR=${env.EDITOR}"
        "VISUAL=${env.VISUAL}"
        "PAGER=${env.PAGER}"
      ];
      WorkingDir = "/workspace";
      User = "${toString users.kc2.uid}:${toString users.kc2.gid}";
      Entrypoint = [ "/bin/bash" "-l" ];
      Cmd = [ ];
      Volumes = {
        "/workspace" = { };
      };
      Labels = {
        "org.opencontainers.image.title" = "Konductor";
        "org.opencontainers.image.description" = "Polyglot development environment";
        "org.opencontainers.image.source" = "https://github.com/braincraftio/konductor";
        "org.opencontainers.image.licenses" = "MIT";
        "org.opencontainers.image.vendor" = "BrainCraft.io";
      };
    };

    maxLayers = 100;
  };
}
