# Custom OpenCode builds

Konductor wraps the selected OpenCode package with its configuration, skills, instructions, and
runtime dependencies. Package selection does not change the defaults for other consumers.

## Home Manager, NixOS, and nix-darwin

Set the unwrapped executable package through the shared module option:

```nix
{ pkgs, ... }: {
  konductor.enable = true;
  konductor.opencode.package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
}
```

The default is `pkgs.opencode`. Existing package overlays remain supported. Pass the raw package,
rather than an already configured Konductor wrapper.

## Development shells

Compose a consumer shell using the same OpenCode input:

```nix
devShells.${system}.opencode =
  inputs.konductor.devShells.${system}.full.withOpencode
    inputs.opencode.packages.${system}.opencode;
```

`withOpencode` rebuilds the shell's configuration and package composition; it does not prepend a
competing executable to an already constructed shell. The `full`, `konductor`, and `frontend` shells
expose this method, as does the Python shell. `withExtraPython` and `withOpencode` preserve each
other's settings when chained.

Enter the consumer's shell with `nix develop .#opencode`. For direnv, point `use flake` at that
consumer output instead of Konductor's default output. Home Manager activation does not change the
package selection of an independent direnv shell. Check `command -v opencode` and
`opencode --version` inside the selected shell.

Pin the consumer's inputs to committed revisions for reproducible sharing. Local dirty Git inputs
are suitable only for development and need their lock entries refreshed after source changes.
