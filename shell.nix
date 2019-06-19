{ nixpkgs ? import <nixos-unstable> {}, compiler ? "ghc865" }:

let

  inherit (nixpkgs) pkgs;

  f = import ./default.nix;

  packageSet = (
    if compiler == "default"
    then  pkgs.haskellPackages
    else  pkgs.haskell.packages.${compiler}
  );

  haskellPackages = (
    packageSet.override {
              overrides = (self: super:
                {
                  ghc = super.ghc // { withPackages = super.ghc.withHoogle; }; # enable hoogle
                  # sdl2 = pkgs.haskell.lib.dontCheck super.sdl2; # fix for sdl2
                  ghcWithPackages = self.ghc.withPackages;
                }
              );
            }
  );

  drv = haskellPackages.callPackage f {};

in

  if pkgs.lib.inNixShell then drv.env else drv
