# src/overlays/python-packages.nix
# Fixes for Python package builds
#
# setproctitle: Disable tests on macOS Tahoe (Darwin 25.x) only.
# The fork_segfault tests trigger SIGSEGV in the nix sandbox on newer
# macOS with Apple Silicon. Linux builds use binary cache unaffected.

_final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_python-final: python-prev: {
      setproctitle = python-prev.setproctitle.overridePythonAttrs (_oldAttrs: {
        doCheck = !prev.stdenv.isDarwin;
      });
    })
  ];
}
