# src/qcow2/konductor-mount-template.nix
# TOML-based virtio disk mount service
#
# Serial IDs are opaque keys (ws, home-1000, pki, kube).
# Mount configuration lives in /var/lib/konductor/services.toml [mounts.*].
# Parsing uses yj (TOML->JSON) + jq -- same strategy as konductor-init.service.

{ pkgs, ... }:

{
  # Trigger konductor-mount@ for all virtio block devices with a serial ID.
  # The mount service validates the serial against services.toml [mounts.*].
  # Unknown serials fail cleanly with an explicit error.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", KERNEL=="vd*", ENV{ID_SERIAL}=="?*", TAG+="systemd", ENV{SYSTEMD_WANTS}="konductor-mount@$env{ID_SERIAL}.service"
  '';

  systemd.services."konductor-mount@" = {
    description = "Mount virtio disk by serial ID: %i";
    after = [ "sysinit.target" "cloud-init.service" ];

    serviceConfig = let
      mountStart = pkgs.writeShellScript "konductor-mount-start" ''
        set -euo pipefail

        SERIAL="$1"
        DEVICE="/dev/disk/by-id/virtio-$SERIAL"
        CONFIG_FILE="/var/lib/konductor/services.toml"

        echo "========================================="
        echo "konductor-mount@$SERIAL.service"
        echo "========================================="

        # Wait for device (max 30s)
        for i in {1..30}; do
          [ -e "$DEVICE" ] && break
          echo "Waiting for device $DEVICE... ($i/30)"
          sleep 1
        done
        if [ ! -e "$DEVICE" ]; then
          echo "ERROR: Device $DEVICE not found after 30s"
          exit 1
        fi

        # Wait for config file (max 60s) -- handles udev vs cloud-init race
        for i in {1..60}; do
          [ -f "$CONFIG_FILE" ] && break
          echo "Waiting for $CONFIG_FILE... ($i/60)"
          sleep 1
        done
        if [ ! -f "$CONFIG_FILE" ]; then
          echo "ERROR: $CONFIG_FILE not found after 60s"
          exit 1
        fi

        # Parse TOML config -- same strategy as konductor-init.service (yj + jq)
        CONFIG_JSON=$(${pkgs.yj}/bin/yj -t < "$CONFIG_FILE")
        MOUNT_CONFIG=$(echo "$CONFIG_JSON" | ${pkgs.jq}/bin/jq -e --arg key "$SERIAL" '.mounts[$key] // empty' 2>/dev/null || true)

        if [ -z "$MOUNT_CONFIG" ]; then
          echo "ERROR: No [mounts.$SERIAL] section in $CONFIG_FILE"
          exit 1
        fi

        FS_TYPE=$(echo "$MOUNT_CONFIG" | ${pkgs.jq}/bin/jq -r '.fstype')
        OWNER=$(echo "$MOUNT_CONFIG" | ${pkgs.jq}/bin/jq -r '.owner')
        GROUP=$(echo "$MOUNT_CONFIG" | ${pkgs.jq}/bin/jq -r '.group')
        MODE=$(echo "$MOUNT_CONFIG" | ${pkgs.jq}/bin/jq -r '.mode')
        MOUNT_POINT=$(echo "$MOUNT_CONFIG" | ${pkgs.jq}/bin/jq -r '.path')

        if [ "$FS_TYPE" = "iso9660" ]; then
          FS_OPTS="ro,nofail"
        else
          FS_OPTS="defaults,nofail"
        fi

        echo "Device: $DEVICE"
        echo "Filesystem: $FS_TYPE"
        echo "Owner: $OWNER:$GROUP"
        echo "Permissions: $MODE"
        echo "Mount Point: $MOUNT_POINT"

        ${pkgs.coreutils}/bin/mkdir -p "$MOUNT_POINT"

        if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
          echo "Already mounted: $MOUNT_POINT"
          exit 0
        fi

        # Format if needed (empty block device)
        EXISTING_FS=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" 2>/dev/null || echo "")

        if [ -z "$EXISTING_FS" ]; then
          if [ "$FS_TYPE" = "iso9660" ]; then
            echo "ERROR: Cannot format iso9660 (read-only)"
            exit 1
          fi

          FORMAT_FS="$FS_TYPE"
          [ "$FORMAT_FS" = "auto" ] && FORMAT_FS="ext4"

          echo "Formatting $DEVICE as $FORMAT_FS..."
          case "$FORMAT_FS" in
            ext4) ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L "$(basename "$MOUNT_POINT")" "$DEVICE" ;;
            xfs)  ${pkgs.xfsprogs}/bin/mkfs.xfs -L "$(basename "$MOUNT_POINT")" "$DEVICE" ;;
            *)    echo "ERROR: Cannot format: $FORMAT_FS"; exit 1 ;;
          esac
        else
          echo "Existing filesystem: $EXISTING_FS"
        fi

        # Mount
        if [ "$FS_TYPE" = "auto" ]; then
          ${pkgs.util-linux}/bin/mount -o "$FS_OPTS" "$DEVICE" "$MOUNT_POINT"
        else
          ${pkgs.util-linux}/bin/mount -t "$FS_TYPE" -o "$FS_OPTS" "$DEVICE" "$MOUNT_POINT"
        fi

        echo "Mounted: $DEVICE -> $MOUNT_POINT"

        # Set ownership and permissions (skip for read-only iso9660)
        if [ "$FS_TYPE" != "iso9660" ]; then
          ${pkgs.coreutils}/bin/chown "$OWNER:$GROUP" "$MOUNT_POINT"
          ${pkgs.coreutils}/bin/chmod "$MODE" "$MOUNT_POINT"
        fi

        echo "========================================="
        echo "Mount complete: $MOUNT_POINT"
        echo "========================================="
      '';

      mountStop = pkgs.writeShellScript "konductor-mount-stop" ''
        set -euo pipefail

        SERIAL="$1"
        CONFIG_FILE="/var/lib/konductor/services.toml"

        if [ ! -f "$CONFIG_FILE" ]; then
          echo "No config file, nothing to unmount"
          exit 0
        fi

        CONFIG_JSON=$(${pkgs.yj}/bin/yj -t < "$CONFIG_FILE")
        MOUNT_POINT=$(echo "$CONFIG_JSON" | ${pkgs.jq}/bin/jq -r --arg key "$SERIAL" '.mounts[$key].path // empty')

        if [ -z "$MOUNT_POINT" ]; then
          echo "No mount config for '$SERIAL', nothing to unmount"
          exit 0
        fi

        echo "Unmounting: $MOUNT_POINT"
        if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
          ${pkgs.util-linux}/bin/umount "$MOUNT_POINT"
          echo "Unmounted: $MOUNT_POINT"
        else
          echo "Not mounted: $MOUNT_POINT"
        fi
      '';
    in {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mountStart} %i";
      ExecStop = "${mountStop} %i";
    };
  };
}
