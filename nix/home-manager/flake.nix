{
  description = "Home Manager configuration for Nix user packages";

  inputs = {
    # USTC 镜像 (github fetcher 的 codeload 302 超时, 改用镜像 tarball)
    nixpkgs.url = "https://mirrors.ustc.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz";
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      overlay = final: prev: {
        damask-solvers = final.callPackage ./packages/damask-solvers.nix { };
        python-damask = final.python3Packages.callPackage ./packages/python-damask.nix { };
        damask = final.callPackage ./packages/damask.nix { };
      };
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ overlay ];
      };
    in {
      overlays.default = overlay;
      packages.${system}.damask = pkgs.damask;
      homeConfigurations."{{env_var 'USER'}}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
