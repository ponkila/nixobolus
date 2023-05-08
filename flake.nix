{
  description = "Nixobolus flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    overrides.url = "path:./overrides";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ethereum-nix = {
      url = "github:nix-community/ethereum.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , darwin
    , disko
    , ethereum-nix
    , home-manager
    , nixos-generators
    , nixpkgs
    , sops-nix
    , overrides
    }@inputs:

    let
      inherit (self) outputs;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      # custom packages -- accessible through 'nix build', 'nix shell', etc
      # TODO -- check that this actually works
      packages = forEachPkgs (pkgs: import ./pkgs { inherit pkgs; });

      # list hostnames from ./hosts
      ls = builtins.readDir ./hosts;
      hostnames = builtins.filter
        (name: builtins.hasAttr name ls && (ls.${name} == "directory"))
        (builtins.attrNames ls);

      # custom formats for nixos-generators
      # other available formats can be found at: https://github.com/nix-community/nixos-generators/tree/master/formats
      customFormats = {
        "netboot-kexec" = {
          formatAttr = "kexecTree";
          imports = [ ./system/formats/netboot-kexec.nix ];
        };
        "copytoram-iso" = {
          formatAttr = "isoImage";
          imports = [ ./system/formats/copytoram-iso.nix ];
          filename = "*.iso";
        };
      };

      modules = [
        ./system
        ./system/ramdisk.nix
        home-manager.nixosModules.home-manager
        disko.nixosModules.disko
        {
          nixpkgs.overlays = [
            ethereum-nix.overlays.default
            outputs.overlays.additions
            outputs.overlays.modifications
          ];
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
          ];
          system.stateVersion = "23.05";
        }
      ];

      homestakeros = {
        localization = {
          hostname = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
            default = "homestaker";
          };
          timezone = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
            default = "Europe/Helsinki";
          };
          keymap = nixpkgs.lib.mkOption {
            type = with nixpkgs.lib.types; either str path;
          };
        };

        mounts = nixpkgs.lib.mkOption {
          type = nixpkgs.lib.types.attrsOf nixpkgs.lib.types.string;
        };

        ssh = {
          privateKeyPath = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.path;
            default = "/var/mnt/secrets/ssh/id_ed25519";
          };
        };

        user = {
          authorizedKeys = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.listOf nixpkgs.lib.types.str;
            default = [ ];
          };
        };

        erigon = {
          enable = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.bool;
            default = false;
          };
          endpoint = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
          datadir = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
        };

        lighthouse = {
          enable = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.bool;
            default = false;
          };
          endpoint = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
          exec.endpoint = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
          slasher = {
            enable = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.bool;
              default = false;
            };
            history-length = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.int;
              default = 4096;
            };
            max-db-size = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.int;
              default = 256;
            };
          };
          mev-boost = {
            endpoint = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.str;
            };
          };
          datadir = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
        };

        mev-boost = {
          enable = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.bool;
            default = false;
          };
        };
      };
    in
    {
      # devshell -- accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # code formatter -- accessible through 'nix fmt'
      formatter = forEachPkgs (pkgs: pkgs.nixpkgs-fmt);

      # nixos-generators entrypoints for each system and hostname combination
      # accessible through 'nix build .#nixobolus.<system_arch>.<hostname>'
      nixobolus = builtins.listToAttrs (map
        (system: {
          name = system;
          value = builtins.listToAttrs (map
            (hostname: {
              name = hostname;
              value = nixos-generators.nixosGenerate {
                inherit modules system customFormats;
                specialArgs = { inherit inputs outputs; };
                format = "netboot-kexec";
              };
            })
            hostnames);
        })
        systems);

      # nixos configuration entrypoints for evaluating
      # accessible through 'nix eval .#nixosConfigurations.<hostname>.config'
      # TODO -- only maps for "x86_64-linux" at the moment
      nixosConfigurations = builtins.listToAttrs (map
        (hostname: {
          name = hostname;
          value = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            inherit modules;
            specialArgs = { inherit inputs outputs; };
          };
        })
        hostnames);

      # nixobolus apps -- accessible through 'nix run .#<script_name>'
      # TODO -- only maps for "x86_64-linux" at the moment
      apps."x86_64-linux" = {
        dinar-ping =
          let
            pkgs = import nixpkgs { system = "x86_64-linux"; };
            my-name = "dinar-ping";
            my-script = pkgs.writeShellScriptBin my-name ''
              ping $(nix eval --raw ../homestaking-infra#nixosConfigurations.dinar-ephemeral-alpha.config.lighthouse.endpoint)
            '';
            my-buildInputs = with pkgs; [ cowsay ddate ];
          in
          pkgs.symlinkJoin {
            name = my-name;
            paths = [ my-script ] ++ my-buildInputs;
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/${my-name} --prefix PATH : $out/bin";
          };
        dinar-latest-block-hash =
          let
            pkgs = import nixpkgs { system = "x86_64-linux"; };
            my-name = "dinar-latest-block-hash";
            my-script = pkgs.writeShellScriptBin my-name ''
              ip=$(nix eval --raw path:../homestaking-infra#nixosConfigurations.dinar-ephemeral-alpha.config.lighthouse.endpoint)
              curl -X POST --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' $ip:5052
            '';
            my-buildInputs = with pkgs; [ cowsay ddate ];
          in
          pkgs.symlinkJoin {
            name = my-name;
            paths = [ my-script ] ++ my-buildInputs;
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/${my-name} --prefix PATH : $out/bin";
          };
      };

      # filters options recursively
      # option exports -- accessible through 'nix eval --json .#exports'
      exports = nixpkgs.lib.attrsets.mapAttrsRecursiveCond
        (v: ! nixpkgs.lib.options.isOption v)
        (k: v: v.type.name)
        homestakeros;

      # usage: https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b
      nixosModules.homestakeros = { config, lib, pkgs, ... }: with lib; rec {
        options = homestakeros;
        config = mkMerge [
          ################################################################### LOCALIZATION
          (mkIf true {
            networking.hostName = options.localization.hostname;
            time.timeZone = options.localization.timezone;
            console.keyMap = options.localization.keymap;
          })

          #################################################################### MOUNTS
          (mkIf true {
            systemd.mounts = builtins.listToAttrs (map
              (mount: {
                enable = mount.enable or true;
                description = mount.description or "Unnamed mount point";
                what = mount.what;
                where = mount.where;
                type = mount.type or "ext4";
                options = mount.options or "defaults";
                before = lib.mkDefault mount.before;
                wantedBy = mount.wantedBy or [ "multi-user.target" ];
              })
              options.mounts);
          })

          #################################################################### SSH (system level)
          (mkIf true {
            services.openssh = {
              enable = true;
              settings.PasswordAuthentication = false;
              hostKeys = [{
                path = options.ssh.privateKeyPath;
                type = "ed25519";
              }];
            };
          })

          #################################################################### USER (core)
          (mkIf true {
            services.getty.autologinUser = "core";
            users.users.core = {
              isNormalUser = true;
              group = "core";
              extraGroups = [ "wheel" ];
              openssh.authorizedKeys.keys = options.user.authorizedKeys;
              shell = pkgs.fish;
            };
            users.groups.core = { };
            environment.shells = [ pkgs.fish ];
            programs.fish.enable = true;

            home-manager.users.core = { pkgs, ... }: {

              sops = {
                defaultSopsFile = ./secrets/default.yaml;
                secrets."wireguard/wg0" = {
                  path = "%r/wireguard/wg0.conf";
                };
                age.sshKeyPaths = [ options.ssh.privateKeyPath ];
              };

              home.packages = with pkgs; [
                file
                tree
                bind # nslookup
              ];

              programs = {
                tmux.enable = true;
                htop.enable = true;
                vim.enable = true;
                git.enable = true;
                fish.enable = true;
                fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";

                home-manager.enable = true;
              };
              home.stateVersion = "23.05";
            };
          })

          #################################################################### WIREGUARD (no options)
          (mkIf true {
            systemd.services.wg0 = {
              enable = true;

              description = "wireguard interface for cross-node communication";
              requires = [ "network-online.target" ];
              after = [ "network-online.target" ];

              serviceConfig = {
                Type = "oneshot";
              };

              script = ''${nixpkgs.wireguard-tools}/bin/wg-quick \
              up /run/user/1000/wireguard/wg0.conf
              '';

              wantedBy = [ "multi-user.target" ];
            };
          })

          #################################################################### ERIGON
          (mkIf (options.erigon.enable) {
            # package
            environment.systemPackages = [
              pkgs.erigon
            ];

            # service
            systemd.user.services.erigon = {
              enable = true;

              description = "execution, mainnet";
              requires = [ "wg0.service" ];
              after = [ "wg0.service" "lighthouse.service" ];

              serviceConfig = {
                Restart = "always";
                RestartSec = "5s";
                Type = "simple";
              };

              script = ''${pkgs.erigon}/bin/erigon \
            --datadir=${options.erigon.datadir} \
            --chain mainnet \
            --authrpc.vhosts="*" \
            --authrpc.addr ${options.erigon.endpoint} \
            --authrpc.jwtsecret=${options.erigon.datadir}/jwt.hex \
            --metrics \
            --externalcl
          '';

              wantedBy = [ "multi-user.target" ];
            };

            # firewall
            networking.firewall = {
              allowedTCPPorts = [ 30303 30304 42069 ];
              allowedUDPPorts = [ 30303 30304 42069 ];
            };
          })

          #################################################################### MEV-BOOST
          (mkIf (options.mev-boost.enable) {
            # podman
            virtualisation.podman.enable = true;
            # dnsname allows containers to use ${name}.dns.podman to reach each other
            # on the same host instead of using hard-coded IPs.
            # NOTE: --net must be the same on the containers, and not eq "host"
            # TODO: extend this with flannel ontop of wireguard for cross-node comms
            virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

            # service
            systemd.user.services.mev-boost = {
              enable = true;

              description = "MEV-boost allows proof-of-stake Ethereum consensus clients to outsource block construction";
              requires = [ "wg0.service" ];
              after = [ "wg0.service" ];

              serviceConfig = {
                Restart = "always";
                RestartSec = "5s";
                Type = "simple";
              };

              script = ''${pkgs.mev-boost}/bin/mev-boost \
                -mainnet \
                -relay-check \
                -relays ${lib.concatStringsSep "," [
                  "https://0xac6e77dfe25ecd6110b8e780608cce0dab71fdd5ebea22a16c0205200f2f8e2e3ad3b71d3499c54ad14d6c21b41a37ae@boost-relay.flashbots.net"
                  "https://0xad0a8bb54565c2211cee576363f3a347089d2f07cf72679d16911d740262694cadb62d7fd7483f27afd714ca0f1b9118@bloxroute.ethical.blxrbdn.com"
                  "https://0x9000009807ed12c1f08bf4e81c6da3ba8e3fc3d953898ce0102433094e5f22f21102ec057841fcb81978ed1ea0fa8246@builder-relay-mainnet.blocknative.com"
                  "https://0xb0b07cd0abef743db4260b0ed50619cf6ad4d82064cb4fbec9d3ec530f7c5e6793d9f286c4e082c0244ffb9f2658fe88@bloxroute.regulated.blxrbdn.com"
                  "https://0x8b5d2e73e2a3a55c6c87b8b6eb92e0149a125c852751db1422fa951e42a09b82c142c3ea98d0d9930b056a3bc9896b8f@bloxroute.max-profit.blxrbdn.com"
                  "https://0x98650451ba02064f7b000f5768cf0cf4d4e492317d82871bdc87ef841a0743f69f0f1eea11168503240ac35d101c9135@mainnet-relay.securerpc.com"
                  "https://0x84e78cb2ad883861c9eeeb7d1b22a8e02332637448f84144e245d20dff1eb97d7abdde96d4e7f80934e5554e11915c56@relayooor.wtf"
                ]} \
                -addr 0.0.0.0:18550
              '';

              wantedBy = [ "multi-user.target" ];
            };
          })

          #################################################################### LIGHTHOUSE
          (mkIf (options.lighthouse.enable) {
            # package
            environment.systemPackages = with pkgs; [
              lighthouse
            ];

            # service
            systemd.user.services.lighthouse = {
              enable = true;

              description = "beacon, mainnet";
              requires = [ "wg0.service" ];
              after = [ "wg0.service" "mev-boost.service" ];

              serviceConfig = {
                Restart = "always";
                RestartSec = "5s";
                Type = "simple";
              };

              script = ''${pkgs.lighthouse}/bin/lighthouse bn \
            --datadir ${options.lighthouse.datadir} \
            --network mainnet \
            --http --http-address ${options.lighthouse.endpoint} \
            --execution-endpoint ${options.lighthouse.exec.endpoint} \
            --execution-jwt ${options.lighthouse.datadir}/jwt.hex \
            --builder ${options.lighthouse.mev-boost.endpoint} \
            --prune-payloads false \
            --metrics \
            ${if options.lighthouse.slasher.enable then
              "--slasher "
              + " --slasher-history-length " + (toString options.lighthouse.slasher.history-length)
              + " --slasher-max-db-size " + (toString options.lighthouse.slasher.max-db-size)
            else "" }
          '';
              wantedBy = [ "multi-user.target" ];
            };

            # firewall
            networking.firewall = {
              allowedTCPPorts = [ 9000 ];
              allowedUDPPorts = [ 9000 ];
              interfaces."wg0".allowedTCPPorts = [
                5052 # lighthouse
              ];
            };
          })
        ];
      };
    };
}
