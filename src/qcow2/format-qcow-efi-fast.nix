# format-qcow-efi-fast.nix
# Custom nixos-generators format that uses make-disk-image-fast.nix
# instead of the standard make-disk-image.nix (which uses slow cptofs).
#
# This format produces the same output as qcow-efi but builds 5-10x faster
# for large closures (100k+ files) by copying files inside the VM using
# native Linux I/O instead of LKL userspace emulation.

{ config, lib, pkgs, modulesPath, ... }:

{
  # Import QEMU guest profile for virtio drivers
  imports = [
    "${toString modulesPath}/profiles/qemu-guest.nix"
  ];

  options = {
    boot.consoles = lib.mkOption {
      default =
        [ "ttyS0" ]
        ++ (lib.optional (pkgs.stdenv.hostPlatform.isAarch) "ttyAMA0,115200")
        ++ (lib.optional (pkgs.stdenv.hostPlatform.isRiscV64) "ttySIF0,115200");
      description = "Kernel console boot flags to pass to boot.kernelParams";
      example = [ "ttyS2,115200" ];
    };
  };

  config = {
    # Root filesystem
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
    };

    # Boot partition (EFI)
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };

    boot.growPartition = true;
    boot.kernelParams = map (c: "console=${c}") config.boot.consoles;
    boot.loader.grub.device = "nodev";
    boot.loader.grub.efiSupport = true;
    boot.loader.grub.efiInstallAsRemovable = true;
    boot.loader.timeout = 0;

    # Use the FAST disk image builder instead of standard make-disk-image.nix
    system.build.qcow-efi-fast = import ./make-disk-image-fast.nix {
      inherit lib config pkgs;
      inherit (config.virtualisation) diskSize;
      format = "qcow2";
      partitionTableType = "efi";
      # Give the VM more memory for faster tar extraction
      memSize = 4096;
    };

    # nixos-generators format metadata
    formatAttr = "qcow-efi-fast";
    fileExtension = ".qcow2";
  };
}
