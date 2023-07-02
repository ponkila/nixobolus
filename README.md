# Nixobolus

Automated creation of bootable NixOS images

## About

This project serves as the backend for [HomestakerOS](https://github.com/ponkila/HomestakerOS), a Web UI designed to generate an integrated network of ephemeral Linux servers. Additionally, it provides modules for our Ethereum infrastructure in [homestaking-infra](https://github.com/ponkila/homestaking-infra), ensuring that everything remain up-to-date and optimized. This project utilizes [ethereum.nix](https://github.com/nix-community/ethereum.nix) for a package management solution for Ethereum clients.

## How does this work?

First, the frontend requests a JSON schema that's generated from the available module options. These options are generated by an exports function, which parses the module options into a more useful format. The exports are fetched using the following command:
```bash
nix eval --json github:ponkila/nixobolus#exports
```
The exports are then utilized to generate an HTML form. The user defines the options within the HTML frontend, and upon form submission, the form payload is sent to Nixobolus using a command as such:
```bash
nix run github:ponkila/nixobolus#buidl --base homestakeros --json '{"erigon":{"enable":true}}'
```
This command triggers the execution of the `scripts/buidl.sh` script, which generates a `/tmp/data.nix` file based on the provided JSON data and initiates the building process. The base configuration is automatically set up to import this file if it exists. The resulting output is stored in the `./result` directory.

## Usage as a Module

To use Nixobolus as a module in your NixOS configuration, you can follow the example provided below. For a practical implementation, refer to our homestaking-infra repository, which demonstrates the modules usage in a real scenario.

```nix
{
  inputs.nixobolus.url = "github:ponkila/nixobolus";

  outputs = { self, nixpkgs, nixobolus }: {
    # Change `yourhostname` to your actual hostname
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      # Customize to your system
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nixobolus.nixosModules.homestakeros
      ];
    };
  };
}
```

