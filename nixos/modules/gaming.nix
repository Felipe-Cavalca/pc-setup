{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
  };

  hardware.steam-hardware.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
    gamemode
    heroic
  ];

  programs.gamemode.enable = true;
}
