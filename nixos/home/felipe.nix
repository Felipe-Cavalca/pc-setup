{ lib, ... }:
let
  wallpaper = "/home/felipe/.local/share/backgrounds/gargantua-realistic.png";
in
{
  home.username = "felipe";
  home.homeDirectory = "/home/felipe";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;

  home.sessionVariables = {
    EDITOR = "code --wait";
    VISUAL = "code --wait";
  };

  home.file.".local/share/backgrounds/gargantua-realistic.png".source =
    ../assets/gargantua-realistic.png;

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };

    "org/gnome/desktop/background" = {
      picture-uri = lib.hm.gvariant.mkString "file://${wallpaper}";
      picture-uri-dark = lib.hm.gvariant.mkString "file://${wallpaper}";
      picture-options = "zoom";
    };

    "org/gnome/desktop/screensaver" = {
      picture-uri = lib.hm.gvariant.mkString "file://${wallpaper}";
    };

    "org/gnome/desktop/media-handling" = {
      automount = false;
      automount-open = false;
    };
  };
}
