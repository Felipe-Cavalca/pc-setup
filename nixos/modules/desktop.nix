{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.printing.enable = true;
  services.flatpak.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    google-chrome
    brave
    bitwarden-desktop
    yubioath-flutter
    vscode
    gnome-tweaks
    gnome-extension-manager
    vlc
    libreoffice
    keepassxc
  ];

  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Google Drive has no official Linux desktop client. rclone is installed in
  # base.nix and can mount/sync Drive without coupling the data disk to boot.
  # Proton Mail/VPN can be added through Flatpak if their native Nix packages
  # are unavailable or lag behind upstream.
}
