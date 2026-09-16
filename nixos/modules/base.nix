{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    allowed-users = [ "@users" ];
    trusted-users = [
      "root"
      "admin"
    ];
  };

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "pt_BR.UTF-8";
  console.keyMap = "br-abnt2";

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    vim
    nano
    htop
    btop
    tree
    unzip
    zip
    p7zip
    unrar
    rsync
    rclone
    pciutils
    usbutils
    efibootmgr
    smartmontools
    ntfs3g
    exfatprogs
  ];

  services.openssh.enable = false;
  services.fstrim.enable = true;
  services.udisks2.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
