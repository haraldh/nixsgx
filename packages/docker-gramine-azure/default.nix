{ lib
, bash
, coreutils
, python3
, dockerTools
, nixsgx
}:
dockerTools.buildImage
{
  name = "gramine-azure";
  tag = "latest";

  copyToRoot = with nixsgx; [
    coreutils
    bash
    azure-dcap-client
    sgx-psw
    gramine
    nixsgx.sgx-dcap.quote_verify
  ];

}
