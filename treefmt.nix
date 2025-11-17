{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs = {
    dart-format.enable = true;
    nixfmt.enable = true;
  };
}
