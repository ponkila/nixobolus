{pkgs ? import <nixpkgs> {}}: {
  # example = pkgs.callPackage ./example { };
  eth-duties = pkgs.callPackage ./eth-duties { };
}
