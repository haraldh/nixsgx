{
  description = "Intel SGX and TDX for nixos";

  nixConfig = {
    extra-substituters = [ "https://attic.teepot.org/cache" ];
    extra-trusted-public-keys = [ "cache:uLQovCi1QU+B4PPXhue3z7y2NqznyEJIsGiENpNZtiI=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    snowfall-lib = {
      url = "github:snowfallorg/lib?ref=c6238c83de101729c5de3a29586ba166a9a65622";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;

      package-namespace = "nixsgx";

      snowfall = {
        namespace = "nixsgx";
      };

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixpkgs-fmt;
      };
    };
}
