{
  inputs = {
    nixpkgs.url = "github:haraldh/nixpkgs/update_sgx";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  description = "SGX packages for nixos";

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;

      package-namespace = "nixsgx";

      snowfall = {
        namespace = "nixsgx";
      };

      alias = {
        packages = {
          default = "all";
        };
      };

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixpkgs-fmt;
      };
    };
}
