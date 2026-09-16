{ pkgs, ... }:
{
  services.xserver = {
    enable = true;
    xkb.layout = "br";
  };

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.printing.enable = true;
  services.flatpak.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
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
  ];

  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Google Drive intentionally uses rclone instead of a required mount.
  # Proton Mail/VPN are intentionally left outside the critical system closure;
  # Flatpak is available for them when desired.
}
