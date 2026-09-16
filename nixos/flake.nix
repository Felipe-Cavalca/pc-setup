{
  description = "Felipe's NixOS workstation setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.np55xdakf2br = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/np55xdakf2br/configuration.nix
        ];
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
