# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

{
  description = "Nixobolus flake";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ethereum.nix
    ethereum-nix = {
      url = "github:nix-community/ethereum.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-generators
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-generators, ethereum-nix, ... }@inputs:

    let
      inherit (self) outputs;
      system = "x86_64-linux";

      forEachSystem = nixpkgs.lib.genAttrs [ 
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      # custom packages
      # acessible through 'nix build', 'nix shell', etc
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});
      packages = forEachPkgs (pkgs: import ./pkgs { inherit pkgs; });
      formatter = forEachPkgs (pkgs: pkgs.nixpkgs-fmt);

      # get hostnames from ./nix_configs/hosts
      ls = builtins.readDir ./hosts;
      hostnames = builtins.filter
        (name: builtins.hasAttr name ls && (ls.${name} == "directory"))
        (builtins.attrNames ls);

      # overlays
      overlays = [ ethereum-nix.overlays.default ];
      pkgs = import nixpkgs { inherit system overlays; };

      # custom formats for nixos-generators
      # other available formats can be found at: https://github.com/nix-community/nixos-generators/tree/master/formats
      customFormats = {
        "kexecTree" = { 
          formatAttr = "kexecTree";
          imports = [ ./system/netboot.nix ]; 
        };
      };
    in {
      # devshell for bootstrapping
      # acessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # nixos-generators
      # available through 'nix build .#your-hostname'
      packages.${system} = builtins.listToAttrs (map (hostname: {
        name = hostname;
        value = nixos-generators.nixosGenerate {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./hosts/${hostname} ];
          customFormats = customFormats;
          format = "kexecTree";
        };
      }) hostnames);

      # nixos configuration entrypoints
      # available through 'nix build .#your-hostname'
      nixosConfigurations = builtins.listToAttrs (map (hostname: {
        name = hostname;
        value = nixpkgs.lib.nixosSystem {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./hosts/${hostname} ];
        };
      }) hostnames);
    };
}