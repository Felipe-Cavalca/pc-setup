{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  networking.networkmanager.enable = true;
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "pt_BR.UTF-8";
  console.keyMap = "br-abnt2";

  users.users.felipe = {
    isNormalUser = true;
    description = "Felipe";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.bashInteractive;
  };

  security.sudo.wheelNeedsPassword = true;

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
    rsync
    rclone
    pciutils
    usbutils
    efibootmgr
    smartmontools
  ];

  services.openssh.enable = false;
  services.fstrim.enable = true;

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
