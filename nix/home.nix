{ pkgs, lib, ... }:
{
  home.username = "liuky3";
  home.homeDirectory = "/home/liuky3";
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    ast-grep
    cliamp
    dotter
    herdr
    wsl2-ssh-agent
    # CUDA 版 llama-cpp（对应 AUR 的 llama.cpp-cuda），构建时间长，需要时解除注释：
    # (llama-cpp.override { cudaSupport = true; })
  ];

  # 把 home-manager profile 的可执行镜像到 ~/.local/bin。
  # 已有同名且不是 symlink 时跳过并告警，避免覆盖手工安装的工具。
  home.activation.linkBins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/bin"
    for f in "$HOME/.local/state/nix/profiles/home-manager/bin"/*; do
      [ -e "$f" ] || continue
      name="$(basename "$f")"
      if [ -e "$HOME/.local/bin/$name" ] && [ ! -L "$HOME/.local/bin/$name" ]; then
        echo "linkBins: skip $name (exists as regular file, left as-is)"
        continue
      fi
      ln -sfn "$f" "$HOME/.local/bin/$name"
    done
  '';
}