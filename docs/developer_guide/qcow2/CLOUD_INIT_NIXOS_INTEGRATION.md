# Cloud-init NixOS Integration Guide

**Generated:** 2026-02-04
**Research Sources:** canonical/cloud-init, NixOS/nixpkgs via DeepWiki MCP
**Target:** NixOS 25.11 + cloud-init 25.2 for KubeVirt Platform-as-a-Service

---

## Executive Summary

This document provides exhaustive guidance for integrating cloud-init with NixOS for the Konductor Platform-as-a-Service. Key findings:

1. **NixOS cloud-init module uses `lib.mkDefault`** - settings MERGE with defaults, use `lib.mkForce` to REPLACE
2. **Removed modules still in NixOS defaults** - `migrator`, `rightscale_userdata` must be explicitly excluded
3. **NixOS distro class has NotImplementedError** - `_write_network`, `apply_locale`, `install_packages`
4. **Serial console logging requires BOTH** - `output:` section AND `logging:` section configuration

---

## 1. Module Reference

### 1.1 Module Stages

Cloud-init runs in 4 stages:
1. **init-local** (`cloud-init init --local`) - Before networking, reads local datasources
2. **init** (`cloud-init init`) - After networking, reads network datasources
3. **config** (`cloud-init modules --mode=config`) - Configuration modules
4. **final** (`cloud-init modules --mode=final`) - Final execution, similar to rc.local

### 1.2 Complete Module Inventory

#### cloud_init_modules (init stage)

| Module | Purpose | NixOS Status | Notes |
|--------|---------|--------------|-------|
| `seed_random` | Seeds system RNG | ✅ WORKS | Universal, no deps |
| `bootcmd` | Early boot commands | ✅ WORKS | Universal, runs shell |
| `write_files` | Write files to filesystem | ✅ WORKS | Universal, key module |
| `growpart` | Expand last partition | ✅ WORKS | Needs `util-linux` |
| `resizefs` | Resize filesystem | ✅ WORKS | Needs `e2fsprogs`/`xfsprogs`/`btrfs-progs` |
| `disk_setup` | Partition/format disks | ⚠️ CAUTION | May conflict with NixOS mounts |
| `mounts` | Configure mounts via fstab | ⚠️ CAUTION | NixOS generates /etc/fstab declaratively |
| `set_hostname` | Set hostname | ✅ WORKS | NixOS patch implements this |
| `update_hostname` | Update hostname | ✅ WORKS | NixOS patch implements this |
| `update_etc_hosts` | Update /etc/hosts | ⚠️ LIMITED | NixOS generates /etc/hosts |
| `ca_certs` | Manage CA certificates | ✅ WORKS | May need NixOS integration |
| `rsyslog` | Configure rsyslog | ❌ SKIP | NixOS uses journald |
| `users_groups` | Create users/groups | ✅ WORKS | Key module for user management |
| `ssh` | Configure SSH | ✅ WORKS | Key module for SSH keys |
| `resolv_conf` | Configure DNS | ⚠️ LIMITED | systemd-resolved on NixOS |
| `migrator` | **REMOVED in 24.1** | ❌ EXCLUDE | No longer exists |

#### cloud_config_modules (config stage)

| Module | Purpose | NixOS Status | Notes |
|--------|---------|--------------|-------|
| `set_passwords` | Set user passwords | ✅ WORKS | Universal |
| `ntp` | Configure NTP | ⚠️ LIMITED | NixOS handles declaratively |
| `timezone` | Set timezone | ❌ NOT IMPL | Raises NotImplementedError on NixOS |
| `runcmd` | Run commands | ✅ WORKS | Key module for custom scripts |
| `locale` | Set locale | ❌ NOT IMPL | Raises NotImplementedError on NixOS |
| `ssh_import_id` | Import SSH keys from LP/GH | ⚠️ UNVERIFIED | Not tested on NixOS |
| `disable_ec2_metadata` | Disable EC2 metadata | ✅ WORKS | Useful for non-EC2 |
| `apt_*` | APT configuration | ❌ SKIP | Debian/Ubuntu only |
| `grub_dpkg` | GRUB config for dpkg | ❌ SKIP | Debian/Ubuntu only |
| `yum_add_repo` | YUM repos | ❌ SKIP | RHEL only |
| `zypper_add_repo` | Zypper repos | ❌ SKIP | SUSE only |
| `snap` | Snap packages | ❌ SKIP | Ubuntu only |
| `ubuntu_pro` | Ubuntu Pro | ❌ SKIP | Ubuntu only |
| `rh_subscription` | RHEL subscription | ❌ SKIP | RHEL only |
| `keyboard` | Keyboard layout | ❌ SKIP | Not for NixOS |
| `wireguard` | WireGuard VPN | ❌ SKIP | Ubuntu only |

#### cloud_final_modules (final stage)

| Module | Purpose | NixOS Status | Notes |
|--------|---------|--------------|-------|
| `scripts_vendor` | Run vendor scripts | ✅ WORKS | Universal |
| `scripts_per_once` | Run scripts once | ✅ WORKS | Universal |
| `scripts_per_boot` | Run scripts every boot | ✅ WORKS | Universal |
| `scripts_per_instance` | Run scripts per instance | ✅ WORKS | Universal |
| `scripts_user` | Run user scripts | ✅ WORKS | Universal |
| `ssh_authkey_fingerprints` | Print SSH key fingerprints | ✅ WORKS | Alternative to keys_to_console |
| `keys_to_console` | Print SSH keys to console | ❌ BROKEN | Helper path wrong for NixOS FHS |
| `phone_home` | Report to remote server | ✅ WORKS | Optional |
| `final_message` | Display final message | ✅ WORKS | Key module |
| `power_state_change` | Handle power state | ✅ WORKS | Optional |
| `package_update_upgrade_install` | Package management | ❌ NOT IMPL | install_packages raises NotImplementedError |
| `rightscale_userdata` | **REMOVED in 24.1** | ❌ EXCLUDE | No longer exists |

---

## 2. NixOS Module Behavior

### 2.1 Why Settings Are Merged (Not Replaced)

The NixOS cloud-init module uses `lib.mkDefault` for all settings:

```nix
# From nixos/modules/services/system/cloud-init.nix
services.cloud-init.settings = {
  cloud_init_modules = lib.mkDefault [
    "migrator"        # ← Still in NixOS defaults despite being REMOVED
    "seed_random"
    # ...
  ];
};
```

When you define your own list, it MERGES with these defaults. To REPLACE, use `lib.mkForce`:

```nix
services.cloud-init.settings = {
  cloud_init_modules = lib.mkForce [ /* your list */ ];
};
```

### 2.2 NixOS Distro Class Limitations

The NixOS distro patch (`0001-add-nixos-support.patch`) implements a minimal distro class:

**Implemented Methods:**
- `_select_hostname` - Hostname selection
- `_write_hostname` - Write hostname to file
- `_read_hostname` - Read hostname
- `_read_system_hostname` - Get system hostname

**NotImplementedError (will crash if called):**
- `_write_network` - Network configuration
- `apply_locale` - Locale setting
- `install_packages` - Package installation

**No-op Methods (do nothing):**
- `package_command` - Package commands
- `set_timezone` - Timezone setting (silent no-op!)
- `update_package_sources` - Update package sources

---

## 3. Recommended Configuration

### 3.1 Complete services.cloud-init.settings for NixOS

```nix
{ config, lib, pkgs, ... }:

{
  services.cloud-init = {
    enable = true;
    network.enable = true;  # Enables systemd-networkd integration

    settings = {
      # ═══════════════════════════════════════════════════════════════════════
      # SYSTEM INFO
      # ═══════════════════════════════════════════════════════════════════════
      system_info = {
        distro = "nixos";
        paths = {
          cloud_dir = "/var/lib/cloud";
          run_dir = "/run/cloud-init";
        };
        network = {
          renderers = [ "networkd" ];  # Force systemd-networkd only
        };
      };

      # ═══════════════════════════════════════════════════════════════════════
      # USERS - Non-deprecated list syntax
      # ═══════════════════════════════════════════════════════════════════════
      users = [
        "default"  # Or specify full user objects
      ];
      disable_root = false;
      preserve_hostname = false;

      # ═══════════════════════════════════════════════════════════════════════
      # DATASOURCE - NoCloud for KubeVirt/QEMU
      # ═══════════════════════════════════════════════════════════════════════
      datasource_list = [ "NoCloud" "ConfigDrive" "None" ];
      datasource = {
        NoCloud = {
          seedfrom = null;  # Use attached ISO
        };
      };

      # ═══════════════════════════════════════════════════════════════════════
      # OUTPUT - Redirect ALL output to serial console (trusted pathway)
      # ═══════════════════════════════════════════════════════════════════════
      output = {
        all = "| tee -a /dev/ttyS0";
      };

      # ═══════════════════════════════════════════════════════════════════════
      # LOGGING - Configure Python logging to serial + journald
      # ═══════════════════════════════════════════════════════════════════════
      # Note: cloud-init uses Python's fileConfig format for logging
      # This is a structured config that gets converted to fileConfig YAML
      _log = [
        ''
        [loggers]
        keys=root,cloudinit

        [handlers]
        keys=consoleHandler,serialHandler

        [formatters]
        keys=simpleFormatter

        [logger_root]
        level=DEBUG
        handlers=consoleHandler

        [logger_cloudinit]
        level=DEBUG
        handlers=consoleHandler,serialHandler
        qualname=cloudinit
        propagate=0

        [handler_consoleHandler]
        class=StreamHandler
        level=DEBUG
        formatter=simpleFormatter
        args=(sys.stderr,)

        [handler_serialHandler]
        class=FileHandler
        level=DEBUG
        formatter=simpleFormatter
        args=('/dev/ttyS0', 'a')

        [formatter_simpleFormatter]
        format=%(asctime)s - %(name)s[%(levelname)s]: %(message)s
        datefmt=%Y-%m-%dT%H:%M:%S
        ''
      ];
      log_cfgs = [ [ "*_log" ] ];

      # ═══════════════════════════════════════════════════════════════════════
      # INIT MODULES - Use lib.mkForce to REPLACE defaults
      # ═══════════════════════════════════════════════════════════════════════
      cloud_init_modules = lib.mkForce [
        # REQUIRED - Core functionality
        "seed_random"
        "bootcmd"
        "write_files"
        "growpart"
        "resizefs"
        "set_hostname"
        "update_hostname"
        "users_groups"
        "ssh"

        # OPTIONAL - Enable if needed
        # "disk_setup"      # Caution: may conflict with NixOS mounts
        # "mounts"          # Caution: NixOS generates fstab declaratively
        # "ca_certs"        # Enable if managing CA certs via cloud-init
        # "update_etc_hosts" # Limited: NixOS generates /etc/hosts

        # EXCLUDED - Not applicable to NixOS
        # "migrator"        # REMOVED in cloud-init 24.1
        # "rsyslog"         # NixOS uses journald
        # "resolv_conf"     # systemd-resolved on NixOS
      ];

      # ═══════════════════════════════════════════════════════════════════════
      # CONFIG MODULES - Use lib.mkForce to REPLACE defaults
      # ═══════════════════════════════════════════════════════════════════════
      cloud_config_modules = lib.mkForce [
        # WORKS on NixOS
        "set_passwords"
        "runcmd"
        "disable_ec2_metadata"

        # OPTIONAL
        # "ntp"             # Limited: NixOS handles NTP declaratively
        # "ssh_import_id"   # Unverified on NixOS

        # EXCLUDED - Raises NotImplementedError or distro-specific
        # "locale"          # NotImplementedError on NixOS
        # "timezone"        # Silent no-op on NixOS (use NixOS config instead)
        # "apt_*"           # Debian/Ubuntu only
        # "grub_dpkg"       # Debian/Ubuntu only
        # "yum_add_repo"    # RHEL only
        # "zypper_add_repo" # SUSE only
        # "snap"            # Ubuntu only
        # "keyboard"        # Not for NixOS
      ];

      # ═══════════════════════════════════════════════════════════════════════
      # FINAL MODULES - Use lib.mkForce to REPLACE defaults
      # ═══════════════════════════════════════════════════════════════════════
      cloud_final_modules = lib.mkForce [
        # WORKS on NixOS
        "scripts_vendor"
        "scripts_per_once"
        "scripts_per_boot"
        "scripts_per_instance"
        "scripts_user"
        "ssh_authkey_fingerprints"  # Use instead of keys_to_console
        "final_message"

        # OPTIONAL
        # "phone_home"      # Enable if reporting to remote server
        # "power_state_change" # Enable if handling power state

        # EXCLUDED
        # "keys_to_console" # BROKEN - helper path wrong for NixOS FHS
        # "rightscale_userdata" # REMOVED in cloud-init 24.1
        # "package_update_upgrade_install" # NotImplementedError on NixOS
      ];
    };
  };
}
```

### 3.2 User-Data Example (YAML format for NoCloud ISO)

```yaml
#cloud-config
# ═══════════════════════════════════════════════════════════════════════════
# Konductor User-Data Template
# Compatible with NixOS cloud-init integration
# ═══════════════════════════════════════════════════════════════════════════

# Users - Use LIST syntax (not deprecated string)
users:
  - name: kc2
    uid: 1001
    groups: docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... user@host
  - name: kc2admin
    uid: 1002
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... user@host
  - name: runner
    uid: 1003
    groups: kc2, wheel, docker, libvirtd, kvm
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true

# Write files
write_files:
  - path: /etc/konductor/boot-time
    content: |
      boot_time=$(date -Iseconds)
    permissions: '0644'

# Boot commands (run early, before other modules)
bootcmd:
  - echo "cloud-init bootcmd starting" > /dev/ttyS0

# Run commands (run after config stage)
runcmd:
  - echo "cloud-init runcmd starting" > /dev/ttyS0
  - systemctl start docker
  - systemctl start libvirtd

# Growpart configuration
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: true

resize_rootfs: true

# Final message
final_message: |
  cloud-init complete
  instance: $INSTANCE_ID
  uptime: $UPTIME
```

---

## 4. Systemd Service Ordering

The NixOS cloud-init module defines these systemd services:

```
cloud-init-local.service
    ├─ wantedBy: multi-user.target
    ├─ before: systemd-networkd.service, dhcpcd.service
    └─ StandardOutput: journal+console

cloud-init.service
    ├─ wantedBy: multi-user.target
    ├─ wants: network-online.target, cloud-init-local.service
    ├─ after: network-online.target, cloud-init-local.service
    ├─ before: sshd.service, sshd-keygen.service
    ├─ requires: network.target
    └─ StandardOutput: journal+console

cloud-config.service
    ├─ wantedBy: multi-user.target
    ├─ wants: network-online.target
    ├─ after: network-online.target, cloud-config.target
    └─ StandardOutput: journal+console

cloud-final.service
    ├─ wantedBy: multi-user.target
    ├─ wants: network-online.target
    ├─ after: network-online.target, cloud-config.service, rc-local.service
    ├─ requires: cloud-config.target
    └─ StandardOutput: journal+console
```

**Key ordering:**
1. `cloud-init-local` runs BEFORE networking
2. `cloud-init` runs AFTER network-online
3. `cloud-config` runs AFTER cloud-init
4. `cloud-final` runs LAST

---

## 5. Logging Configuration Deep Dive

### 5.1 Understanding output vs logging

| Configuration | Controls | Destination |
|---------------|----------|-------------|
| `output:` | stdout/stderr of shell commands | File/device/pipe |
| `logging:` (via `log_cfgs`) | Python logging messages | Handlers (file/syslog/stream) |

For serial console as trusted pathway, configure BOTH:

```yaml
# Output section - captures command output
output:
  all: "| tee -a /dev/ttyS0"

# Logging section - captures Python log messages
log_cfgs:
  - - |
      [loggers]
      keys=root,cloudinit
      [handlers]
      keys=serialHandler
      [formatters]
      keys=timestampFormatter
      [logger_root]
      level=DEBUG
      handlers=serialHandler
      [logger_cloudinit]
      level=DEBUG
      handlers=serialHandler
      qualname=cloudinit
      propagate=0
      [handler_serialHandler]
      class=FileHandler
      level=DEBUG
      formatter=timestampFormatter
      args=('/dev/ttyS0', 'a')
      [formatter_timestampFormatter]
      format=%(asctime)s - %(filename)s[%(levelname)s]: %(message)s
      datefmt=%Y-%m-%dT%H:%M:%S%z
```

### 5.2 Preventing "no logging configured" Warning

The warning appears when `log_cfgs` is empty or no configuration loads successfully.
Ensure at least one valid logging configuration is present.

---

## 6. Platform Integration Checklist

### For Konductor Platform-as-a-Service:

- [ ] `lib.mkForce` on all module lists
- [ ] Exclude `migrator` (removed in 24.1)
- [ ] Exclude `rightscale_userdata` (removed in 24.1)
- [ ] Exclude `keys_to_console` (broken on NixOS)
- [ ] Use `ssh_authkey_fingerprints` instead of `keys_to_console`
- [ ] Configure `output:` to pipe to `/dev/ttyS0`
- [ ] Configure `log_cfgs` with serial handler
- [ ] Set `system_info.network.renderers = [ "networkd" ]`
- [ ] Set `datasource_list = [ "NoCloud" "ConfigDrive" "None" ]`
- [ ] Use list syntax for `users:` (not deprecated string)
- [ ] Don't use `timezone` module (silent no-op on NixOS)
- [ ] Don't use `locale` module (NotImplementedError on NixOS)
- [ ] Don't use `install_packages` (NotImplementedError on NixOS)

---

## 7. NixOS-Native Alternatives

For functionality that cloud-init can't provide on NixOS:

| cloud-init Module | NixOS Native Alternative |
|-------------------|-------------------------|
| `locale` | `i18n.defaultLocale` |
| `timezone` | `time.timeZone` |
| `ntp` | `services.ntp` or `services.chrony` |
| `package_*` | Nix expressions in `environment.systemPackages` |
| `apt_*` / `yum_*` | N/A - NixOS uses Nix package manager |
| `grub_*` | `boot.loader.grub.*` |
| `rsyslog` | `services.rsyslogd` or journald (default) |
| `resolv_conf` | `networking.nameservers` / `services.resolved` |
| `keyboard` | `console.keyMap` / `services.xserver.xkb.layout` |

---

## 8. Troubleshooting

### 8.1 "Module X has been removed from cloud-init"

**Cause:** Module is in `/etc/cloud/cloud.cfg` but removed from cloud-init codebase.
**Fix:** Use `lib.mkForce` on module lists to exclude removed modules.

### 8.2 "Unable to activate module keys-to-console"

**Cause:** Helper script path assumes FHS, NixOS uses `/nix/store`.
**Fix:** Exclude `keys_to_console`, use `ssh_authkey_fingerprints` instead.

### 8.3 "No netplan API available" / "ovs-vsctl not in PATH"

**Cause:** cloud-init probes for all network backends.
**Fix:** Set `system_info.network.renderers = [ "networkd" ]`.

### 8.4 "'users' of type str is deprecated"

**Cause:** Using `users: "default"` string syntax.
**Fix:** Use list syntax: `users: [ "default" ]` or `users: [ { name: "default" } ]`.

### 8.5 "NotImplementedError" crashes

**Cause:** Calling functionality not implemented in NixOS distro class.
**Fix:** Exclude modules that call `apply_locale`, `install_packages`, `_write_network`.

---

## References

- [canonical/cloud-init](https://github.com/canonical/cloud-init) - Upstream cloud-init
- [NixOS/nixpkgs cloud-init module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/system/cloud-init.nix)
- [NixOS/nixpkgs cloud-init patch](https://github.com/NixOS/nixpkgs/blob/master/pkgs/tools/virtualization/cloud-init/0001-add-nixos-support.patch)
- [NixOS/nixpkgs cloud-init test](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/cloud-init.nix)
