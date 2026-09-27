{
  description = "Custom Nix packages maintained outside nixpkgs";

  inputs = {
    # USTC 镜像 (github fetcher 的 codeload 302 超时, 改用镜像 tarball)
    nixpkgs.url = "https://mirrors.ustc.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      damask-solvers = pkgs.callPackage ./packages/damask-solvers.nix { };
      python-damask = pkgs.python3Packages.callPackage ./packages/python-damask.nix { };
      damask = pkgs.callPackage ./packages/damask.nix {
        inherit damask-solvers python-damask;
      };
      # nixpkgs builds Whisper only; SenseVoice/Paraformer need the ONNX engines.
      voxtype-onnx = pkgs.voxtype.override { onnxSupport = true; };
      # On a non-NixOS host the system ALSA config routes `default` to PipeWire,
      # but nix alsa-lib only searches its own store path for that plugin.
      # Wrapping (instead of overriding postFixup) keeps the cached binary.
      voxtype = pkgs.symlinkJoin {
        name = "voxtype-${voxtype-onnx.version}";
        paths = [ voxtype-onnx ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/voxtype \
            --set-default ALSA_PLUGIN_DIR ${pkgs.pipewire}/lib/alsa-lib
        '';
        inherit (voxtype-onnx) meta version;
      };
    in {
      # Ordinary software is installed and upgraded through `nix profile`.
      # Keep this flake limited to locally maintained packages and nixpkgs
      # builds that need non-default options.
      packages.${system} = {
        inherit damask voxtype;
      };
    };
}
