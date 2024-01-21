# Nixobolus

This project serves a couple of essential modules that are designed for [HomestakerOS](https://github.com/ponkila/HomestakerOS), a web UI that generates an integrated network of ephemeral Linux servers. These modules are also used in [our Ethereum infrastructure](https://github.com/ponkila/homestaking-infra), ensuring up-to-date and optimized functionality. Nixobolus utilizes [ethereum.nix](https://github.com/nix-community/ethereum.nix) as a package management solution for Ethereum-related components.

## How does this work?

First, the frontend requests a JSON schema that's generated from the available module options. This schema is generated by an exports function, which parses the module options into a more useful format. The exports are fetched using the following command:
```bash
nix eval --json github:ponkila/nixobolus#exports.homestakeros
```
The exports are then utilized to generate an HTML form. The user defines the options within the HTML frontend and upon form submission, the form payload is sent to Nixobolus using a command as such:
```bash
nix run github:ponkila/nixobolus#buidl -- --base homestakeros '{"execution":{"erigon":{"enable":true}}}'
```
This command triggers the execution of the `scripts/buidl.sh` script, which generates a `/tmp/data.nix` file based on the provided JSON data and initiates the building process. The base configuration is automatically set up to import this file if it exists. By default, the resulting build symlinks are stored in the `./result` directory.

**It is important to note that while the current build script performs as intended, HomestakerOS has its own script derived from this one to meet its specific requirements and additional features.**

## Usage as a Module

To use Nixobolus as a module in your NixOS configuration, you can follow the example provided below. For a practical implementation, refer to our homestaking-infra repository, which demonstrates the modules usage in a real scenario.

```nix
{
  inputs = {
    nixobolus.url = "github:ponkila/nixobolus";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixobolus }: {
    nixosConfigurations = {
      # Change `yourhostname` to your actual hostname
      yourhostname = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          nixobolus.nixosModules.homestakeros
          {
            homestakeros = { ... };
          }
        ];
      };
    };
  };
}
```
