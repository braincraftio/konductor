# src/qcow2/konductor-mount-template.nix
# Systemd template service for convention-based virtio disk mounting
#
# Serial ID Convention (≤20 chars, [A-Za-z0-9_.+-] only):
#   Format: <fstype>-<user>-<mode>-<path>
#
#   Components:
#     fstype = e4 (ext4), iso (iso9660), xfs, auto
#     user   = owner username OR "root"
#     mode   = 3-digit octal permissions
#     path   = mount point with "/" encoded as "." (e.g., h.alice = /home/alice)
#
#   Examples (all use kc2 group GID 1001 for shared access):
#     e4-alice-700-h.alice   → ext4, alice:kc2, 700, /home/alice
#     e4-root-775-h.Git      → ext4, root:kc2, 775, /home/Git
#     iso-root-755-m.kube    → iso9660, root:root, 755 (ro), /m/kube
#     e4-run-775-workspace   → ext4, runner:kc2, 775, /workspace
#
# The systemd unit is a simple parser - the serial string contains all instructions.

{ pkgs, ... }:

{
  systemd.services."konductor-mount@" = {
    description = "Mount virtio disk by serial ID: %i";
    after = [ "local-fs-pre.target" ];
    before = [ "local-fs.target" ];

    serviceConfig = let
      mountStart = pkgs.writeShellScript "konductor-mount-start" ''
        set -euo pipefail

        SERIAL="$1"
        DEVICE="/dev/disk/by-id/virtio-$SERIAL"

        echo "========================================="
        echo "konductor-mount@$SERIAL.service"
        echo "========================================="
        echo "Serial ID: $SERIAL"

        # Wait for device to appear (max 30s)
        for i in {1..30}; do
          if [ -e "$DEVICE" ]; then
            break
          fi
          echo "Waiting for device $DEVICE... ($i/30)"
          sleep 1
        done

        if [ ! -e "$DEVICE" ]; then
          echo "ERROR: Device $DEVICE not found after 30s"
          exit 1
        fi

        echo "Device: $DEVICE"

        # =====================================================================
        # Parse Serial ID: <fstype>-<user>-<mode>-<path>
        # =====================================================================
        IFS='-' read -r FSTYPE_CODE OWNER MODE PATH_ENCODED <<< "$SERIAL"

        if [ -z "$FSTYPE_CODE" ] || [ -z "$OWNER" ] || [ -z "$MODE" ] || [ -z "$PATH_ENCODED" ]; then
          echo "ERROR: Invalid serial format: $SERIAL"
          echo "Expected: <fstype>-<user>-<mode>-<path>"
          echo "Example: e4-alice-700-h.alice"
          exit 1
        fi

        # Decode filesystem type
        case "$FSTYPE_CODE" in
          e4)   FS_TYPE="ext4" ;;
          iso)  FS_TYPE="iso9660" ;;
          xfs)  FS_TYPE="xfs" ;;
          auto) FS_TYPE="auto" ;;
          *)
            echo "ERROR: Unknown filesystem type code: $FSTYPE_CODE"
            echo "Allowed: e4 (ext4), iso (iso9660), xfs, auto"
            exit 1
            ;;
        esac

        # Decode path: dots become slashes, prepend /
        MOUNT_POINT=$(echo "$PATH_ENCODED" | ${pkgs.gnused}/bin/sed 's/\./\//g')
        if [[ ! "$MOUNT_POINT" =~ ^/ ]]; then
          MOUNT_POINT="/$MOUNT_POINT"
        fi

        # Validate mode is 3-digit octal
        if ! [[ "$MODE" =~ ^[0-7]{3}$ ]]; then
          echo "ERROR: Invalid mode: $MODE (must be 3-digit octal)"
          exit 1
        fi

        # Determine group based on filesystem type and owner
        # All shared paths use kc2 group (GID 1001) - baked-in least-privilege group
        if [ "$FS_TYPE" = "iso9660" ]; then
          # ISO9660 is always root:root (read-only secret volumes)
          GROUP="root"
          FS_OPTS="ro,nofail"
        elif [ "$OWNER" = "root" ]; then
          # root-owned paths use root:kc2 (shared)
          GROUP="kc2"
          FS_OPTS="defaults,nofail"
        else
          # User-owned paths use <user>:kc2
          GROUP="kc2"
          FS_OPTS="defaults,nofail"

          # Verify user exists
          if ! ${pkgs.coreutils}/bin/id "$OWNER" &>/dev/null; then
            echo "ERROR: User '$OWNER' does not exist"
            echo "Create user in cloud-init before mounting:"
            echo "  users:"
            echo "    - name: $OWNER"
            echo "      uid: XXXX"
            echo "      groups: kc2"
            exit 1
          fi
        fi

        echo "Filesystem: $FS_TYPE"
        echo "Owner: $OWNER:$GROUP"
        echo "Permissions: $MODE"
        echo "Mount Point: $MOUNT_POINT"
        echo "Mount Options: $FS_OPTS"

        # Create mount point
        ${pkgs.coreutils}/bin/mkdir -p "$MOUNT_POINT"

        # Check if already mounted
        if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
          echo "Already mounted: $MOUNT_POINT"
          exit 0
        fi

        # Mount with specified or auto-detected filesystem type
        if [ "$FS_TYPE" = "auto" ]; then
          # Auto-detect filesystem type
          DETECTED_FS=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" || echo "unknown")
          echo "Auto-detected filesystem: $DETECTED_FS"
          ${pkgs.util-linux}/bin/mount -o "$FS_OPTS" "$DEVICE" "$MOUNT_POINT"
        else
          # Use specified filesystem type
          ${pkgs.util-linux}/bin/mount -t "$FS_TYPE" -o "$FS_OPTS" "$DEVICE" "$MOUNT_POINT"
        fi

        echo "Mounted: $DEVICE → $MOUNT_POINT"

        # Set ownership and permissions
        ${pkgs.coreutils}/bin/chown "$OWNER:$GROUP" "$MOUNT_POINT"
        ${pkgs.coreutils}/bin/chmod "$MODE" "$MOUNT_POINT"

        echo "Ownership: $OWNER:$GROUP"
        echo "Permissions: $MODE"
        echo "========================================="
        echo "Mount complete: $MOUNT_POINT"
        echo "========================================="
      '';

      mountStop = pkgs.writeShellScript "konductor-mount-stop" ''
        set -euo pipefail

        SERIAL="$1"

        # Parse serial ID to get mount point
        IFS='-' read -r FSTYPE_CODE OWNER MODE PATH_ENCODED <<< "$SERIAL"

        MOUNT_POINT=$(echo "$PATH_ENCODED" | ${pkgs.gnused}/bin/sed 's/\./\//g')
        if [[ ! "$MOUNT_POINT" =~ ^/ ]]; then
          MOUNT_POINT="/$MOUNT_POINT"
        fi

        echo "Unmounting: $MOUNT_POINT"

        # Unmount if mounted
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
