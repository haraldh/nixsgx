{
  description = "Intel SGX and TDX for nixos";

  nixConfig = {
    extra-substituters = [ "https://attic.teepot.org/cache" ];
    extra-trusted-public-keys = [ "cache:uBVyXkiuk10QNZcN5y5mIjjtuox79LeIFnqiCzE2TH4=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11-small";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;

      package-namespace = "nixsgx";

      snowfall = {
        namespace = "nixsgx";
      };

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixfmt-tree;
      };
    };
}
