# src/lib/meta.nix
# Metadata, labels, and descriptions

{ versions }:

{
  # OCI image labels
  oci = {
    title = "Konductor";
    description = "Polyglot development environment";
    source = "https://github.com/braincraftio/konductor";
    licenses = "MIT";
    vendor = "BrainCraft.io";
    inherit (versions.image) created;
  };

  # VM metadata
  vm = {
    name = "konductor";
    description = "Konductor development VM";
    defaultUser = "kc2";
    defaultPassword = "";
  };

  # Project metadata
  project = {
    description = "Konductor: Polyglot Development Environment";
    homepage = "https://github.com/braincraftio/konductor";
  };
}
