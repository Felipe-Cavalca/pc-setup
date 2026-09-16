{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/users.nix
    ../../modules/desktop.nix
    ../../modules/development.nix
    ../../modules/gaming.nix
    ../../modules/agent.nix
  ];

  networking.hostName = "felipe-nix";

  # Windows keeps its existing ESP mounted at /efi. Kernels and initrds live
  # on a separate FAT32 XBOOTLDR partition at /boot, both on the 256 GB NVMe.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 8;
    xbootldrMountPoint = "/boot";
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/efi";
  };

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  powerManagement.enable = true;
  services.fwupd.enable = true;
  services.thermald.enable = true;

  # Never add the 1 TB data disk here as a required filesystem. If it is ever
  # mounted later, do it explicitly by UUID after installation.
  system.stateVersion = "26.05";
}
