{ pkgs, ... }:
{
  users.mutableUsers = true;

  users.groups.pcsetup-agent = { };

  users.users = {
    root.hashedPassword = "!";

    felipe = {
      isNormalUser = true;
      description = "Felipe";
      extraGroups = [
        "networkmanager"
        "libvirtd"
        "pcsetup-agent"
      ];
      shell = pkgs.bashInteractive;
    };

    admin = {
      isNormalUser = true;
      description = "Administrador de recuperacao";
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      shell = pkgs.bashInteractive;
    };

    publico = {
      isNormalUser = true;
      description = "Publico";
      shell = pkgs.bashInteractive;
    };

    agent = {
      isNormalUser = true;
      description = "AI agent";
      group = "pcsetup-agent";
      extraGroups = [ ];
      home = "/home/agent";
      createHome = true;
      homeMode = "0750";
      shell = pkgs.bashInteractive;
      hashedPassword = "!";
    };
  };

  security.sudo.wheelNeedsPassword = true;

  systemd.tmpfiles.rules = [
    "d /home/felipe/Apps 0750 felipe users -"
    "d /home/felipe/Games 0750 felipe users -"
    "d /home/felipe/Drive 0750 felipe users -"
    "d /home/felipe/VMs 0750 felipe users -"
    "d /home/felipe/Containers 0750 felipe users -"
    "d /home/felipe/Backups 0750 felipe users -"
    "d /home/felipe/Shared 0750 felipe users -"
    "d /home/felipe/Dev 2770 felipe pcsetup-agent -"
    "d /home/agent/Dev 2770 agent pcsetup-agent -"
  ];
}
