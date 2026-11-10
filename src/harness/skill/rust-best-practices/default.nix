{ pkgs }:
{
  scope = "practitioner";
  # Upstream runtime skill from the pinned beautiful-rust package (no evals/).
  directory = "${pkgs.beautiful-rust}/${pkgs.beautiful-rust.skillsDir}/rust-best-practices";
}
