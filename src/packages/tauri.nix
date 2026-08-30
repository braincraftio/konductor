# src/packages/tauri.nix
# Tauri 2.x Desktop Application Build Dependencies
#
# Provides all system libraries required to build Tauri applications on Linux.
# macOS and Windows have different requirements handled by their native toolchains.
#
# Reference: https://tauri.app/start/prerequisites/#linux
# DeepWiki guidance: Include openssl in buildInputs, pkg-config in nativeBuildInputs,
# set OPENSSL_NO_VENDOR=1 to prevent openssl-sys from vendoring.
#
# Portability Notes:
# Nix builds link against /nix/store libraries. For distributable binaries:
# - Use patchelf to change interpreter and RPATH
# - The devshell includes these tools for post-build patching

{ pkgs, lib }:

let
  inherit (pkgs) stdenv;
in

rec {
  # ===========================================================================
  # Build Tools (nativeBuildInputs)
  # ===========================================================================
  # These are tools that run during the build process
  buildTools = with pkgs; [
    pkg-config # Required for finding system libraries
    perl # Required by openssl-sys build script
  ];

  # ===========================================================================
  # Binary Portability Tools (for creating distributable binaries)
  # ===========================================================================
  # These tools help create portable binaries that work outside Nix
  portabilityTools = lib.optionals stdenv.hostPlatform.isLinux (with pkgs; [
    patchelf # Modify ELF binaries (interpreter, RPATH)
    file # Identify file types
  ]);

  # ===========================================================================
  # Core Libraries (buildInputs)
  # ===========================================================================
  # SSL/TLS - Required by many Rust crates (reqwest, hyper-tls, etc.)
  sslLibs = with pkgs; [
    openssl # Provides headers via openssl.dev and runtime via openssl.out
  ];

  # Compression libraries - Required by Rust crates using xz/zstd
  compressionLibs = with pkgs; [
    xz # liblzma for LZMA compression
    zstd # libzstd for Zstandard compression
  ];

  # ===========================================================================
  # Linux GUI Libraries (buildInputs) - Only on Linux
  # ===========================================================================
  # GTK and related libraries for Tauri's webview
  gtkLibs = lib.optionals stdenv.hostPlatform.isLinux (with pkgs; [
    gtk3
    glib
    cairo
    pango
    gdk-pixbuf
    librsvg
    atk
  ]);

  # WebKitGTK 4.1 - Tauri 2.x webview (Linux only)
  webkitLibs = lib.optionals stdenv.hostPlatform.isLinux (with pkgs; [
    webkitgtk_4_1 # WebKit2GTK 4.1 for Tauri 2.x
    libsoup_3 # HTTP library used by WebKitGTK
  ]);

  # System tray support (Linux only)
  trayLibs = lib.optionals stdenv.hostPlatform.isLinux (with pkgs; [
    libayatana-appindicator # System tray icons
  ]);

  # Additional Linux system libraries
  systemLibs = lib.optionals stdenv.hostPlatform.isLinux (with pkgs; [
    dbus # D-Bus IPC
    libxkbcommon # Keyboard handling
  ]);

  # ===========================================================================
  # Aggregated Package Lists
  # ===========================================================================

  # All packages needed during build (nativeBuildInputs in Nix terms)
  nativeBuildInputs = buildTools;

  # All packages needed for linking (buildInputs in Nix terms)
  buildInputs = sslLibs ++ compressionLibs ++ gtkLibs ++ webkitLibs ++ trayLibs ++ systemLibs;

  # Combined list for devshell's nativeBuildInputs (which includes both)
  packages = nativeBuildInputs ++ buildInputs ++ portabilityTools;

  # ===========================================================================
  # Environment Variables
  # ===========================================================================
  env = {
    # Prevent openssl-sys from vendoring OpenSSL - use Nix-provided instead
    OPENSSL_NO_VENDOR = "1";

    # Guide Rust sys crates to use pkg-config
    ZSTD_SYS_USE_PKG_CONFIG = "true";

    # Ensure Tauri doesn't try to download WebView2 on Linux
    TAURI_SKIP_WEBVIEW_CHECK = "1";
  };

  # ===========================================================================
  # Shell Hook
  # ===========================================================================
  # Constructs LD_LIBRARY_PATH for runtime library discovery
  shellHook = ''
    # Runtime libraries for Rust crates compiled within devshell
    # This ensures cargo-installed binaries can find their dependencies
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (
      sslLibs ++ compressionLibs ++ gtkLibs ++ webkitLibs
    )}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Ensure Nix-provided binaries take precedence over ~/.cargo/bin
    # This prevents stale cargo-installed binaries from being used
    export PATH="${lib.makeBinPath packages}:$PATH"

    # Helper function to make Tauri binaries portable (FHS-compatible)
    # Usage: tauri-patch-binary <path-to-binary>
    # This patches the interpreter and clears RPATH so the binary uses system libraries
    tauri-patch-binary() {
      local binary="$1"
      if [ -z "$binary" ]; then
        echo "Usage: tauri-patch-binary <path-to-binary>"
        echo "Example: tauri-patch-binary target/release/myapp"
        return 1
      fi
      if [ ! -f "$binary" ]; then
        echo "Error: File not found: $binary"
        return 1
      fi
      echo "Patching $binary for portability..."
      # Set standard FHS interpreter
      patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$binary" 2>/dev/null || \
        patchelf --set-interpreter /lib/ld-linux-x86-64.so.2 "$binary" 2>/dev/null || \
        echo "Warning: Could not set interpreter (may not be ELF or already patched)"
      # Clear RPATH so system libraries are used
      patchelf --remove-rpath "$binary" 2>/dev/null || true
      echo "Done. Binary should now work on standard Linux systems."
      echo "Note: Target system must have GTK3, WebKitGTK 4.1, and other deps installed."
    }

    # Helper to check binary's current interpreter and dependencies
    tauri-check-binary() {
      local binary="$1"
      if [ -z "$binary" ]; then
        echo "Usage: tauri-check-binary <path-to-binary>"
        return 1
      fi
      echo "=== Binary Info ==="
      file "$binary"
      echo ""
      echo "=== Interpreter ==="
      patchelf --print-interpreter "$binary" 2>/dev/null || echo "(not an ELF or no interpreter)"
      echo ""
      echo "=== RPATH ==="
      patchelf --print-rpath "$binary" 2>/dev/null || echo "(no RPATH)"
      echo ""
      echo "=== Required Libraries ==="
      ldd "$binary" 2>/dev/null | head -20
    }
  '';

  # ===========================================================================
  # pkg-config paths for development headers
  # ===========================================================================
  # This ensures pkg-config finds Nix-provided libraries instead of system ones
  pkgConfigPath = pkgs.lib.makeSearchPath "lib/pkgconfig" (
    sslLibs ++ compressionLibs ++ gtkLibs ++ webkitLibs ++ trayLibs
  );
}
