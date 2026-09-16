{ pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };

  programs.git.enable = true;

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
