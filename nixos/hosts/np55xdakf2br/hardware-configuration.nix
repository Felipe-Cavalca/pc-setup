{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # INSTALLATION PLACEHOLDER
  #
  # nixos/scripts/install.sh replaces this file with the output of
  # `nixos-generate-config --root /mnt --show-hardware-config` only after
  # validating that /, /boot and /efi are all on the same <= 400 GiB disk
  # containing the Windows Boot Manager.
  #
  # UUIDs are intentionally not guessed. The 1 TB data disk must not appear as
  # a required filesystem in the generated file.

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];

  boot.kernelModules = [ "kvm-intel" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
