{ lib
, stdenv
, systemd
, nixsgx
,
}:
stdenv.mkDerivation rec {
  inherit (nixsgx.sgx-dcap) version;
  pname = "libsgx-ae-qe3";

  outputs = [ "dev" "out" ];

  nativeBuildInputs = [
    systemd
  ];

  buildInputs = [
    nixsgx.sgx-dcap
  ];

  unpackPhase = ''
    cp -av ${nixsgx.sgx-dcap}/${pname} .
    chmod -R u+w .
  '';

  buildPhase = ''
    mkdir out
    make DESTDIR=$(pwd)/out -C ${pname}/output install
  '';

  # sigh... Intel!
  installPhase = ''
    runHook preInstall
    mkdir $out
    cp -av out/usr/. $out/
    runHook postInstall
  '';

  doCheck = false;

  meta = with lib; {
    description = "Intel(R) Software Guard Extensions Data Center Attestation Primitives";
    homepage = "https://github.com/intel/SGXDataCenterAttestationPrimitives";
    platforms = [ "x86_64-linux" ];
    license = with licenses; [ bsd3 ];
  };
}
