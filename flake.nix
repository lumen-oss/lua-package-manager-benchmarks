{
  description = "Benchmarks of Lua package managers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lux.url = "github:lumen-oss/lux";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      lib =
        with nixpkgs.lib;
        nixpkgs.lib
        // {
          foreach =
            xs: f:
            foldr recursiveUpdate { } (
              if isList xs then
                map f xs
              else if isAttrs xs then
                mapAttrsToList f xs
              else
                throw "foreach: expected list or attrset but got ${typeOf xs}"
            );
          findModulesList =
            dir:
            pipe dir [
              builtins.readDir
              (filterAttrs (name: type: type == "directory" || hasSuffix ".nix" name && name != "default.nix"))
              attrNames
              (map (f: "${dir}/${f}"))
            ];
        };
    in
    {
      inherit lib;
    }
    // lib.foreach nixpkgs.legacyPackages (
      system: pkgs':
      let
        pkgs = pkgs'.extend inputs.lux.overlays.default;
        lde = pkgs.callPackage ./lde.nix { };
        benchInputs = with pkgs; [
          hyperfine
          lux-cli
          lde
          luarocks
          lua5_1
          pkg-config
        ];
        packages = {
          busted-cold = pkgs.writeShellApplication {
            name = "busted-cold";
            runtimeInputs = benchInputs;
            text = ''
              TMPBASE=$(mktemp -d)
              trap 'rm -rf "$TMPBASE"' EXIT

              hyperfine \
                --warmup 0 \
                --runs 5 \
                --export-markdown "$TMPBASE/busted-cold.md" \
                --prepare "rm -rf $TMPBASE/lux"   "lx --tree $TMPBASE/lux install busted" \
                --prepare "rm -rf $TMPBASE/lde"   "lde  --tree $TMPBASE/lde   install rocks:busted" \
                --prepare "rm -rf $TMPBASE/rocks" "luarocks --tree $TMPBASE/rocks install busted RT_DIR=${pkgs.libc.out}"

              cat "$TMPBASE/busted-cold.md"
            '';
          };

          busted-warm = pkgs.writeShellApplication {
            name = "busted-warm";
            runtimeInputs = benchInputs;
            text = ''
              TMPBASE=$(mktemp -d)
              trap 'rm -rf "$TMPBASE"' EXIT

              lx       --tree "$TMPBASE/lux"   install busted 2>/dev/null
              lde      --tree "$TMPBASE/lde"   install rocks:busted 2>/dev/null
              luarocks --tree "$TMPBASE/rocks" install busted RT_DIR=${pkgs.libc.out} 2>/dev/null

              hyperfine \
                --warmup 2 \
                --runs 10 \
                --export-markdown "$TMPBASE/busted-warm.md" \
                "lx       --tree $TMPBASE/lux --no-prompt install busted" \
                "lde      --tree $TMPBASE/lde             install rocks:busted" \
                "luarocks --tree $TMPBASE/rocks           install busted RT_DIR=${pkgs.libc.out}"

              cat "$TMPBASE/busted-warm.md"
            '';
          };

          lfs-build = pkgs.writeShellApplication {
            name = "lfs-build";
            runtimeInputs = benchInputs;
            text = ''
              TMPBASE=$(mktemp -d)
              trap 'rm -rf "$TMPBASE"' EXIT

              hyperfine \
                --warmup 0 \
                --runs 5 \
                --export-markdown "$TMPBASE/lfs.md" \
                --prepare "rm -rf $TMPBASE/lux"   "lx       --tree $TMPBASE/lux   install luafilesystem" \
                --prepare "rm -rf $TMPBASE/lde"   "lde      --tree $TMPBASE/lde   install rocks:luafilesystem" \
                --prepare "rm -rf $TMPBASE/rocks" "luarocks --tree $TMPBASE/rocks install luafilesystem RT_DIR=${pkgs.libc.out}"

              cat "$TMPBASE/lfs.md"
            '';
          };

        };
      in
      {
        legacyPackages.${system} = pkgs;
        devShells.${system}.default = pkgs.mkShell {
          name = "devShell";
          buildInputs = (
            lib.mapAttrsToList (_: attr: attr) packages
            ++ benchInputs
          );
        };
      }
    );
}
