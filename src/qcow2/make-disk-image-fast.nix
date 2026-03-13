# make-disk-image-fast.nix
# High-performance disk image builder that copies files INSIDE the VM
# instead of using cptofs (LKL) from outside.
#
# Why this is faster:
# - cptofs runs a Linux kernel in userspace (LKL) with 4KB buffers
# - cptofs is single-threaded, ~9 syscalls per file
# - For 100k files, cptofs takes 40+ minutes
#
# This builder:
# - Boots a real QEMU VM with the Nix store shared via virtiofs
# - Copies files using native Linux tools inside the VM
# - Uses real ext4 with proper I/O scheduling and caching
# - 5-10x faster for large file counts

{ pkgs
, lib
, config
, # Disk configuration
  diskSize ? "auto"
, additionalSpace ? "512M"
, bootSize ? "256M"
, # Partition table: "efi", "hybrid", "legacy", "legacy+boot", "legacy+gpt", "none"
  partitionTableType ? "efi"
, # Filesystem
  fsType ? "ext4"
, label ? "nixos"
, # Output format: "raw", "qcow2", "qcow2-compressed"
  format ? "qcow2"
, # Image name
  name ? "nixos-disk-image"
, baseName ? "nixos"
, # Boot
  installBootLoader ? true
, touchEFIVars ? false
, OVMF ? pkgs.OVMF.fd
, efiFirmware ? OVMF.firmware
, efiVariables ? OVMF.variables
, # VM resources
  memSize ? 4096
, # Additional content
  contents ? [ ]
, additionalPaths ? [ ]
, copyChannel ? false
, configFile ? null
, # Determinism
  deterministic ? true
, rootGPUID ? "F222513B-DED1-49FA-B591-20CE86A2FE7F"
, rootFSUID ? (if fsType == "ext4" then rootGPUID else null)
, # Post-processing
  postVM ? ""
,
}:

assert (lib.assertOneOf "partitionTableType" partitionTableType [
  "legacy"
  "legacy+boot"
  "legacy+gpt"
  "efi"
  "efixbootldr"
  "hybrid"
  "none"
]);

let
  formatCompressed = format == "qcow2-compressed";
  actualFormat = if formatCompressed then "qcow2" else format;
  compress = lib.optionalString formatCompressed "-c";

  filename = "${baseName}." + {
    qcow2 = "qcow2";
    vdi = "vdi";
    vpc = "vhd";
    raw = "img";
  }.${actualFormat} or actualFormat;

  rootPartition = {
    legacy = "1";
    "legacy+boot" = "2";
    "legacy+gpt" = "2";
    efi = "2";
    efixbootldr = "3";
    hybrid = "3";
  }.${partitionTableType};

  useEFIBoot = touchEFIVars;
  nixpkgs = lib.cleanSource pkgs.path;

  channelSources = pkgs.runCommand "nixos-${config.system.nixos.version}" { } ''
    mkdir -p $out
    cp -prd ${nixpkgs.outPath} $out/nixos
    chmod -R u+w $out/nixos
    if [ ! -e $out/nixos/nixpkgs ]; then
      ln -s . $out/nixos/nixpkgs
    fi
    rm -rf $out/nixos/.git
    echo -n ${config.system.nixos.versionSuffix} > $out/nixos/.version-suffix
  '';

  basePaths = [ config.system.build.toplevel ] ++ lib.optional copyChannel channelSources;
  additionalPaths' = lib.subtractLists basePaths additionalPaths;

  closureInfo = pkgs.closureInfo {
    rootPaths = basePaths ++ additionalPaths';
  };

  blockSize = toString (4 * 1024);

  # Tools needed in preVM (host) and buildCommand (VM)
  binPath = lib.makeBinPath (with pkgs; [
    rsync
    util-linux
    parted
    e2fsprogs
    dosfstools
    config.system.build.nixos-install
    nixos-enter # standalone package, not config.system.build
    nix
    coreutils
    gnutar
    gzip
    systemdMinimal
  ] ++ lib.optional deterministic gptfdisk
  ++ stdenv.initialPath);

  # Partition scripts
  partitionDiskScript = {
    legacy = ''
      parted --script $diskImage -- \
        mklabel msdos \
        mkpart primary ext4 1MiB 100%
    '';
    "legacy+boot" = ''
      parted --script $diskImage -- \
        mklabel msdos \
        mkpart primary fat32 1MiB $bootSizeMiB \
        set 1 boot on \
        mkpart primary ext4 $bootSizeMiB 100%
    '';
    "legacy+gpt" = ''
      parted --script $diskImage -- \
        mklabel gpt \
        mkpart no-fs 1MiB 2MiB \
        set 1 bios_grub on \
        mkpart primary ext4 2MiB 100%
    '';
    efi = ''
      parted --script $diskImage -- \
        mklabel gpt \
        mkpart ESP fat32 8MiB $bootSizeMiB \
        set 1 boot on \
        mkpart primary ext4 $bootSizeMiB 100%
      ${lib.optionalString deterministic ''
        sgdisk \
          --disk-guid=97FD5997-D90B-4AA3-8D16-C1723AEA73C \
          --partition-guid=1:1C06F03B-704E-4657-B9CD-681A087A2FDC \
          --partition-guid=2:${rootGPUID} \
          $diskImage
      ''}
    '';
    efixbootldr = ''
      parted --script $diskImage -- \
        mklabel gpt \
        mkpart ESP fat32 8MiB 100MiB \
        set 1 boot on \
        mkpart BOOT fat32 100MiB $bootSizeMiB \
        set 2 bls_boot on \
        mkpart ROOT ext4 $bootSizeMiB 100%
    '';
    hybrid = ''
      parted --script $diskImage -- \
        mklabel gpt \
        mkpart ESP fat32 8MiB $bootSizeMiB \
        set 1 boot on \
        mkpart no-fs 0 1024KiB \
        set 2 bios_grub on \
        mkpart primary ext4 $bootSizeMiB 100%
    '';
    none = "";
  }.${partitionTableType};

  # Content copying (for additional files)
  sources = map (x: x.source) contents;
  targets = map (x: x.target) contents;
  modes = map (x: x.mode or "''") contents;
  users = map (x: x.user or "''") contents;
  groups = map (x: x.group or "''") contents;

  # preVM: Create disk, partition, format (runs on HOST)
  preVM = ''
    export PATH=${binPath}:$PATH

    mkdir -p $out

    # Calculate sizes
    mebibyte=$(( 1024 * 1024 ))
    bootSize=$(numfmt --from=iec '${bootSize}')
    bootSizeMiB=$(( bootSize / 1024 / 1024 ))MiB

    ${if diskSize == "auto" then ''
      # Calculate required space from closure
      closureSize=$(cat ${closureInfo}/total-nar-size)
      # Add 100% overhead for filesystem metadata + work space, plus additional space
      additionalSpace=$(numfmt --from=iec '${additionalSpace}')
      diskSize=$(( closureSize * 2 + additionalSpace + bootSize ))
      # Round up to nearest MiB
      diskSize=$(( (diskSize / mebibyte + 1) * mebibyte ))
      echo "Auto-calculated disk size: $diskSize bytes ($(( diskSize / mebibyte )) MiB)"
    '' else ''
      diskSize=$(( ${toString diskSize} * mebibyte ))
    ''}

    # Create raw disk image
    diskImage=nixos.raw
    truncate -s "$diskSize" $diskImage

    # Partition the disk
    ${partitionDiskScript}

    # Format root partition using offset (for partitioned disks)
    ${if partitionTableType != "none" then ''
      eval $(partx $diskImage -o START,SECTORS --nr ${rootPartition} --pairs)
      sectorsToBytes() { echo $(( $1 * 512 )); }
      sectorsToKilobytes() { echo $(( $1 * 512 / 1024 )); }
      mkfs.${fsType} -b ${blockSize} -F -L ${label} $diskImage \
        -E offset=$(sectorsToBytes $START) $(sectorsToKilobytes $SECTORS)K
    '' else ''
      mkfs.${fsType} -b ${blockSize} -F -L ${label} $diskImage
    ''}

    echo "=== FAST IMAGE BUILDER: Disk prepared on host ==="
    echo "File copying will happen INSIDE the VM (no cptofs!)"
  '' + lib.optionalString touchEFIVars ''
    efiVars=$out/efi-vars.fd
    cp ${efiVariables} $efiVars
    chmod 0644 $efiVars
  '';

  # postVM: Convert to final format (runs on HOST after VM exits)
  finalPostVM = ''
    ${if actualFormat == "raw" then ''
      mv $diskImage $out/${filename}
    '' else ''
      ${pkgs.qemu-utils}/bin/qemu-img convert -f raw -O ${actualFormat} ${compress} $diskImage $out/${filename}
    ''}

    mkdir -p $out/nix-support
    echo "file ${actualFormat}-image $out/${filename}" >> $out/nix-support/hydra-build-products
  '' + postVM;

in
pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand name
  {
    inherit preVM;
    postVM = finalPostVM;
    inherit memSize;

    passthru = { inherit closureInfo; };

    buildInputs = with pkgs; [
      util-linux
      e2fsprogs
      dosfstools
      rsync
      coreutils
      config.system.build.nixos-install
      nixos-enter
      nix
    ];

    QEMU_OPTS = lib.concatStringsSep " " (
      lib.optional useEFIBoot "-drive if=pflash,format=raw,unit=0,readonly=on,file=${efiFirmware}"
      ++ lib.optionals touchEFIVars [
        "-drive if=pflash,format=raw,unit=1,file=$efiVars"
      ]
      ++ lib.optionals (OVMF.systemManagementModeRequired or false) [
        "-machine"
        "q35,smm=on"
        "-global"
        "driver=cfi.pflash01,property=secure,value=on"
      ]
    );

    enableParallelBuilding = true;
  }
    ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      export PATH=${binPath}:$PATH

      echo ""
      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║           FAST DISK IMAGE BUILDER (no cptofs!)                ║"
      echo "║   Running INSIDE VM with /nix/store shared via virtiofs       ║"
      echo "╚═══════════════════════════════════════════════════════════════╝"
      echo ""

      rootDisk=${if partitionTableType != "none" then "/dev/vda${rootPartition}" else "/dev/vda"}

      # Set filesystem UUID for determinism (before mounting)
      ${lib.optionalString (fsType == "ext4" && deterministic) ''
        tune2fs -U ${rootFSUID} -c 0 -i 0 $rootDisk
      ''}

      # Make systemd-boot find ESP without udev
      mkdir -p /dev/block
      ln -s /dev/vda1 /dev/block/254:1

      # Mount root partition
      mountPoint=/mnt
      mkdir -p $mountPoint
      mount $rootDisk $mountPoint

      # Create and mount boot partition for EFI
      ${lib.optionalString (partitionTableType == "efi" || partitionTableType == "hybrid") ''
        mkdir -p $mountPoint/boot
        mkfs.vfat -n ESP /dev/vda1
        mount /dev/vda1 $mountPoint/boot
        ${lib.optionalString touchEFIVars "mount -t efivarfs efivarfs /sys/firmware/efi/efivars"}
      ''}
      ${lib.optionalString (partitionTableType == "efixbootldr") ''
        mkdir -p $mountPoint/{boot,efi}
        mkfs.vfat -n ESP /dev/vda1
        mkfs.vfat -n BOOT /dev/vda2
        mount /dev/vda1 $mountPoint/efi
        mount /dev/vda2 $mountPoint/boot
        ${lib.optionalString touchEFIVars "mount -t efivarfs efivarfs /sys/firmware/efi/efivars"}
      ''}
      ${lib.optionalString (partitionTableType == "legacy+boot") ''
        mkdir -p $mountPoint/boot
        mkfs.vfat -n BOOT /dev/vda1
        mount /dev/vda1 $mountPoint/boot
      ''}

      echo "=== Step 1: Copy additional contents ==="
      # Copy arbitrary files into the image (rsync with modes)
      set -f
      sources_=(${lib.concatStringsSep " " sources})
      targets_=(${lib.concatStringsSep " " targets})
      modes_=(${lib.concatStringsSep " " modes})
      set +f

      for ((i = 0; i < ''${#targets_[@]}; i++)); do
        source="''${sources_[$i]}"
        target="''${targets_[$i]}"
        mode="''${modes_[$i]}"

        if [ -n "$mode" ]; then
          rsync_chmod_flags="--chmod=$mode"
        else
          rsync_chmod_flags=""
        fi
        rsync_flags="-a --no-o --no-g $rsync_chmod_flags"

        if [[ "$source" =~ '*' ]]; then
          mkdir -p $mountPoint/$target
          for fn in $source; do
            rsync $rsync_flags "$fn" $mountPoint/$target/
          done
        else
          mkdir -p $mountPoint/$(dirname $target)
          if [ -e $mountPoint/$target ]; then
            echo "duplicate entry $target -> $source"
            exit 1
          elif [ -d $source ]; then
            rsync $rsync_flags $source/ $mountPoint/$target
          else
            rsync $rsync_flags $source $mountPoint/$target
          fi
        fi
      done

      echo "=== Step 2: Initialize Nix database ==="
      export HOME=$TMPDIR
      export NIX_STATE_DIR=$TMPDIR/state
      nix-store --load-db < ${closureInfo}/registration

      chmod 755 "$TMPDIR"

      echo "=== Step 3: Run nixos-install (FAST - using native Linux I/O) ==="
      echo "Copying $(wc -l < ${closureInfo}/store-paths) store paths..."
      echo "Source: /nix/store (virtiofs shared)"
      echo "Target: $mountPoint"
      echo ""

      # nixos-install copies the closure and sets up the system
      # This is FAST because /nix/store is already mounted via virtiofs
      nixos-install --root $mountPoint --no-bootloader --no-root-passwd \
        --system ${config.system.build.toplevel} \
        ${if copyChannel then "--channel ${channelSources}" else "--no-channel-copy"} \
        --substituters ""

      ${lib.optionalString (additionalPaths' != []) ''
        echo "Copying additional paths..."
        nix --extra-experimental-features nix-command copy --to $mountPoint --no-check-sigs ${lib.concatStringsSep " " additionalPaths'}
      ''}

      echo "=== Step 4: Install configuration.nix ==="
      mkdir -p $mountPoint/etc/nixos
      ${lib.optionalString (configFile != null) ''
        cp ${configFile} $mountPoint/etc/nixos/configuration.nix
      ''}

      echo "=== Step 5: Install bootloader ==="
      ${lib.optionalString installBootLoader ''
        # Create device symlinks if GRUB expects different device names
        ${lib.optionalString config.boot.loader.grub.enable (
          lib.concatMapStringsSep "\n" (device:
            lib.optionalString (device != "/dev/vda") ''
              mkdir -p "$(dirname ${device})"
              ln -sf /dev/vda ${device}
            ''
          ) config.boot.loader.grub.devices
        )}

        export HOME=$TMPDIR
        NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root $mountPoint -- \
          /nix/var/nix/profiles/system/bin/switch-to-configuration boot
      ''}

      echo "=== Step 6: Set ownership for contents ==="
      # Set the ownerships of the contents
      targets_=(${lib.concatStringsSep " " targets})
      users_=(${lib.concatStringsSep " " users})
      groups_=(${lib.concatStringsSep " " groups})
      for ((i = 0; i < ''${#targets_[@]}; i++)); do
        target="''${targets_[$i]}"
        user="''${users_[$i]}"
        group="''${groups_[$i]}"
        if [ -n "$user$group" ]; then
          nixos-enter --root $mountPoint -- chown -R "$user:$group" "$target"
        fi
      done

      echo "=== Step 7: Finalize filesystem ==="
      umount -R $mountPoint

      # Set deterministic timestamps
      ${lib.optionalString (fsType == "ext4") ''
        tune2fs -T now ${lib.optionalString deterministic "-U ${rootFSUID}"} -c 0 -i 0 $rootDisk
        ${lib.optionalString deterministic "tune2fs -f -T 19700101 $rootDisk"}
      ''}

      echo ""
      echo "╔═══════════════════════════════════════════════════════════════╗"
      echo "║                    IMAGE BUILD COMPLETE!                      ║"
      echo "╚═══════════════════════════════════════════════════════════════╝"
    ''
)
