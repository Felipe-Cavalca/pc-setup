{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # IMPORTANT:
  # Replace this file during installation with the output of:
  #   nixos-generate-config --show-hardware-config
  #
  # Filesystems and UUIDs are deliberately NOT committed here because they
  # depend on the partitions created next to Windows on the 256 GB NVMe.
  # Do not add the 1 TB data drive as a required filesystem for installation.

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
