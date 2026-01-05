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
#     path   = mount point with "/" encoded as "." and abbreviations:
#              h = home, m = mnt, w = workspace, u = $OWNER
#
#   Path Encoding (to fit 20 char limit):
#     h.u       → /home/$OWNER (e.g., /home/usrbinkat)
#     m.kube    → /mnt/kube
#     w         → /workspace
#
#   Workspace Convention:
#     /workspace/<server_fqdn>/<namespace>/<repo_name>/
#     Examples:
#       /workspace/git.braincraft.io/braincraft/k9/
#       /workspace/github.com/user/repo/
#
#   Examples (all use kc2 group GID 1001 for shared access):
#     e4-usrbinkat-775-w          → ext4, root:kc2, 775, /workspace
#     e4-alice-700-h.u       → ext4, alice:kc2, 700, /home/alice
#     iso-root-755-m.kube    → iso9660, root:root, 755 (ro), /mnt/kube
#
# The systemd unit parses and expands the serial string into mount instructions.

{ pkgs, ... }:

{
  # udev rules to auto-start konductor-mount@ services for matching virtio disks
  # Matches serial IDs with pattern: <fstype>-<user>-<mode>-<path>
  # e.g., e4-usrbinkat-775-w, iso-root-755-m.kube
  services.udev.extraRules = ''
    # Auto-start konductor-mount@ for virtio disks with convention-based serials
    # Pattern: (e4|iso|xfs|auto)-<user>-<mode>-<path>
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_SERIAL}=="e4-*", TAG+="systemd", ENV{SYSTEMD_WANTS}="konductor-mount@$env{ID_SERIAL}.service"
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_SERIAL}=="iso-*", TAG+="systemd", ENV{SYSTEMD_WANTS}="konductor-mount@$env{ID_SERIAL}.service"
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_SERIAL}=="xfs-*", TAG+="systemd", ENV{SYSTEMD_WANTS}="konductor-mount@$env{ID_SERIAL}.service"
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_SERIAL}=="auto-*", TAG+="systemd", ENV{SYSTEMD_WANTS}="konductor-mount@$env{ID_SERIAL}.service"
  '';

  systemd.services."konductor-mount@" = {
    description = "Mount virtio disk by serial ID: %i";
    # Run after basic system is up - no 'before' constraint to avoid cycles
    # when udev triggers this service after boot
    after = [ "sysinit.target" ];

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

        # Decode path: dots become slashes, expand abbreviations, prepend /
        # Abbreviations: h=home, m=mnt, w=workspace, u=$OWNER
        MOUNT_POINT=$(echo "$PATH_ENCODED" | ${pkgs.gnused}/bin/sed 's/\./\//g')

        # Expand abbreviations (order matters: do component expansions first)
        # ^h/ or ^h$ → home
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E 's#^h(/|$)#home\1#')
        # ^m/ or ^m$ → mnt
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E 's#^m(/|$)#mnt\1#')
        # ^w/ or ^w$ → workspace
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E 's#^w(/|$)#workspace\1#')
        # /u$ → /$OWNER (final component only)
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E "s#/u\$#/$OWNER#")
        # ^u$ → $OWNER (single component)
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E "s#^u\$#$OWNER#")

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

        # Check if disk has a filesystem, format if empty
        EXISTING_FS=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" 2>/dev/null || echo "")

        if [ -z "$EXISTING_FS" ]; then
          echo "No filesystem detected on $DEVICE"

          if [ "$FS_TYPE" = "iso9660" ]; then
            echo "ERROR: Cannot format iso9660 filesystem (read-only)"
            exit 1
          fi

          # Determine filesystem to create
          if [ "$FS_TYPE" = "auto" ]; then
            FORMAT_FS="ext4"
          else
            FORMAT_FS="$FS_TYPE"
          fi

          echo "Formatting $DEVICE as $FORMAT_FS..."
          case "$FORMAT_FS" in
            ext4)
              ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L "$(basename "$MOUNT_POINT")" "$DEVICE"
              ;;
            xfs)
              ${pkgs.xfsprogs}/bin/mkfs.xfs -L "$(basename "$MOUNT_POINT")" "$DEVICE"
              ;;
            *)
              echo "ERROR: Cannot auto-format filesystem type: $FORMAT_FS"
              exit 1
              ;;
          esac
          echo "Formatted $DEVICE as $FORMAT_FS"
        else
          echo "Existing filesystem: $EXISTING_FS"
        fi

        # Mount with specified or auto-detected filesystem type
        if [ "$FS_TYPE" = "auto" ]; then
          # Re-detect filesystem type after potential format
          DETECTED_FS=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" || echo "unknown")
          echo "Auto-detected filesystem: $DETECTED_FS"
          ${pkgs.util-linux}/bin/mount -o "$FS_OPTS" "$DEVICE" "$MOUNT_POINT"
        else
          # Use specified filesystem type
          ${pkgs.util-linux}/bin/mount -t "$FS_TYPE" -o "$FS_OPTS" "$DEVICE" "$MOUNT_POINT"
        fi

        echo "Mounted: $DEVICE → $MOUNT_POINT"

        # Set ownership and permissions (skip for read-only filesystems like iso9660)
        if [ "$FS_TYPE" != "iso9660" ]; then
          ${pkgs.coreutils}/bin/chown "$OWNER:$GROUP" "$MOUNT_POINT"
          ${pkgs.coreutils}/bin/chmod "$MODE" "$MOUNT_POINT"
          echo "Ownership: $OWNER:$GROUP"
          echo "Permissions: $MODE"
        else
          echo "Skipping chown/chmod for read-only filesystem"
        fi
        echo "========================================="
        echo "Mount complete: $MOUNT_POINT"
        echo "========================================="
      '';

      mountStop = pkgs.writeShellScript "konductor-mount-stop" ''
        set -euo pipefail

        SERIAL="$1"

        # Parse serial ID to get mount point
        IFS='-' read -r FSTYPE_CODE OWNER MODE PATH_ENCODED <<< "$SERIAL"

        # Decode path: dots become slashes, expand abbreviations, prepend /
        MOUNT_POINT=$(echo "$PATH_ENCODED" | ${pkgs.gnused}/bin/sed 's/\./\//g')
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E 's#^h(/|$)#home\1#')
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E 's#^m(/|$)#mnt\1#')
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E 's#^w(/|$)#workspace\1#')
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E "s#/u\$#/$OWNER#")
        MOUNT_POINT=$(echo "$MOUNT_POINT" | ${pkgs.gnused}/bin/sed -E "s#^u\$#$OWNER#")
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
