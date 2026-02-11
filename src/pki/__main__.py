#!/usr/bin/env python3
"""Entry point: python3 /path/to/pki/ or python3 -m pki"""

import os
import sys


def main() -> int:
    # Ensure package is importable when invoked as python3 /path/to/pki/
    here = os.path.dirname(os.path.abspath(__file__))
    parent = os.path.dirname(here)
    if parent not in sys.path:
        sys.path.insert(0, parent)

    try:
        from cryptography import x509  # noqa: F401
    except ImportError:
        print(
            "Error: 'cryptography' library is required.\n"
            "\n"
            "Install via nix:\n"
            "  nix-shell -p 'python3.withPackages (ps: [ps.cryptography])'\n"
            "\n"
            "Or add to NixOS configuration:\n"
            "  environment.systemPackages = [ pkgs.python3Packages.cryptography ];",
            file=sys.stderr,
        )
        return 1

    from pki.cli import run
    return run()


if __name__ == "__main__":
    sys.exit(main())
