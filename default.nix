{ mkDerivation, apecs, base, grid, lens, sdl2, sdl2-image, stdenv
, text, vector
}:
mkDerivation {
  pname = "nethask";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    apecs base grid lens sdl2 sdl2-image text vector
  ];
  license = "unknown";
  hydraPlatforms = stdenv.lib.platforms.none;
}
