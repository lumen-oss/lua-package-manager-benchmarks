{
  pkgs,
  system,
}:

let
  releaseTag = "v0.10.0";
  platform_attrs = {
    "aarch64-darwin" = {
      url = "https://github.com/lde-org/lde/releases/download/${releaseTag}/lde-macos-aarch64";
      sha256 = "bbae095d5b601aabf8b029ef2efc16316d77d8e5ff1f73d2a3d5815503b38bf5";
    };
    "aarch64-linux" = {
      url = "https://github.com/lde-org/lde/releases/download/${releaseTag}/lde-linux-aarch64";
      sha256 = "affb2e4cdde49208464187d39224463883947e5e862604c89cfd0441d07f9cb7";
    };
    "x86_64-linux" = {
      url = "https://github.com/lde-org/lde/releases/download/${releaseTag}/lde-linux-x86-64";
      sha256 = "de725821b3ddcceebe9c7503891c5b31d8a17eb44fb7dbbe59ae676213fc39e0";
    };
  };
in
pkgs.stdenv.mkDerivation {
  pname = "lde";
  version = releaseTag;
  src = pkgs.fetchurl platform_attrs.${system};
  nativeBuildInputs = with pkgs; [
    pkg-config
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = with pkgs; [
    glibc
    gcc-unwrapped
    openssl
    zlib
  ];
  unpackPhase = "true";

  installPhase = ''
    install -D "$src" "$out/bin/lde"
    runHook postInstall
  '';

  postInstall = ''
    wrapProgram "$out/bin/lde" \
      --prefix LD_LIBRARY_PATH : ${
        pkgs.lib.makeLibraryPath (
          with pkgs;
          [
            openssl
            zlib
          ]
        )
      }
  '';
}

