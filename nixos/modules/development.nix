{ pkgs, ... }:
{
  programs.git.enable = true;

  # Rootless Docker preserves the "daily user is not admin" model. The normal
  # docker group is deliberately not granted because it is root-equivalent.
  virtualisation.docker = {
    enable = false;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    git
    gh
    powershell
    vscode
    nodejs_24
    go
    php
    phpPackages.composer
    python3
    jq
    yq-go
    ripgrep
    fd
    fzf
    direnv
    nix-direnv
    docker-compose
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
