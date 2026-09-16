{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/desktop.nix
    ../../modules/development.nix
    ../../modules/gaming.nix
  ];

  networking.hostName = "felipe-nix";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  powerManagement.enable = true;
  services.fwupd.enable = true;
  services.thermald.enable = true;

  # The real partition layout is generated during installation.
  # This repository intentionally does not use disko or any automatic
  # partitioning so the 1 TB data drive cannot be accidentally reformatted.

  system.stateVersion = "26.05";
}
