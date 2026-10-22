{
  description = "Minimal repro: xeus-lua PR #62 makes a cell's locals invisible to its last expression";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # xeus-lua has needed xeus 6 since 0.9.0, and Nixpkgs is still on 5.2.4, so
        # build the two we need here. Both sides of the comparison get exactly the
        # same ones.
        xeus6 = pkgs.xeus.overrideAttrs (_old: {
          version = "6.0.5";
          src = pkgs.fetchFromGitHub {
            owner = "jupyter-xeus";
            repo = "xeus";
            tag = "6.0.5";
            hash = "sha256-nbjq4dzrukVsZI6X3lWpr9oCZV5IUu/vkqSNKD7o3vo=";
          };
        });

        xeusZmq4 = (pkgs.xeus-zmq.override { xeus = xeus6; }).overrideAttrs (_old: {
          version = "4.0.0";
          src = pkgs.fetchFromGitHub {
            owner = "jupyter-xeus";
            repo = "xeus-zmq";
            tag = "4.0.0";
            hash = "sha256-Ux8klPh33XWFu9eu+GTk5ZcqIcoP/GM4/J1uaz9xRHI=";
          };
        });

        # The only difference between the two builds is `rev`. Widgets are off so the
        # closure stays small; they have nothing to do with the bug.
        mkXeusLua =
          { label, rev, hash }:
          pkgs.stdenv.mkDerivation {
            pname = "xeus-lua-${label}";
            version = builtins.substring 0 12 rev;

            src = pkgs.fetchFromGitHub {
              owner = "jupyter-xeus";
              repo = "xeus-lua";
              inherit rev hash;
            };

            nativeBuildInputs = [ pkgs.cmake ];
            buildInputs = [
              pkgs.cppzmq
              pkgs.libuuid
              pkgs.lua5_4
              pkgs.nlohmann_json
              pkgs.openssl
              pkgs.zeromq
              xeus6
              xeusZmq4
            ];

            cmakeFlags = [
              (pkgs.lib.cmakeBool "XLUA_WITH_XWIDGETS" false)
              (pkgs.lib.cmakeBool "XLUA_WITH_XCANVAS" false)
              (pkgs.lib.cmakeBool "XEUS_LUA_USE_LUAJIT" false)
            ];

            meta.mainProgram = "xlua";
          };

        before = mkXeusLua {
          label = "before";
          # Parent of the PR #62 merge
          rev = "46b00ca34388ac187bcd83d1d749adcb96315126";
          hash = "sha256-hgs5GqkXnSAmFCR1kS3yW9ZrEmdSCyrKZa7vBrPMcOc=";
        };

        after = mkXeusLua {
          label = "after";
          # The PR #62 merge commit
          rev = "0462359f60cbf1e368f13d689e42fd882acf34f6";
          hash = "sha256-qo3Qndia/tGpFWW/Lo9ApKtEL4w3/4zokRc9e3yoSh0=";
        };

        python = pkgs.python3.withPackages (ps: [ ps.jupyter-client ]);

        repro = pkgs.writeShellApplication {
          name = "xeus-lua-pr62-repro";
          runtimeInputs = [ python ];
          text = ''
            exec python3 ${./repro.py} "${before}" "${after}"
          '';
        };
      in
      {
        packages = {
          inherit before after repro;
          default = repro;
        };

        apps.default = {
          type = "app";
          program = pkgs.lib.getExe repro;
        };
      }
    );
}
