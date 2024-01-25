{ lib
, buildEnv
, stdenv
, symlinkJoin
, nixsgx
}:
let
  container = stdenv.mkDerivation {
    name = "container";

    src = with nixsgx; [
      docker-gramine-azure
      docker-gramine-dcap
    ];

    unpackPhase = "true";

    installPhase = ''
      set -x
      mkdir -p $out
      cp -vr $src $out
    '';
  };
in
symlinkJoin {
  name = "all";
  paths = with nixsgx;[
    container
    azure-dcap-client
    gramine
    protobufc
    restart-aesmd
    sgx-dcap
    sgx-psw
    sgx-sdk
    sgx-ssl
  ];
}
