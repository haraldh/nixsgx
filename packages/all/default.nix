{ lib
, symlinkJoin
, nixsgx
}:
symlinkJoin
{
  name = "all";

  paths = with nixsgx; [
    azure-dcap-client
    gramine
    libsgx-ae-id-enclave
    libsgx-ae-qe3
    libsgx-ae-qve
    libsgx-ae-tdqe
    libsgx-dcap-default-qpl
    libsgx-dcap-ql
    libsgx-dcap-quote-verify
    libsgx-pce-logic
    libsgx-qe3-logic
    libsgx-ra-network
    libsgx-ra-uefi
    libsgx-tdx-logic
    libtdx-attest
    sgx-dcap
    #    sgx-dcap-pccs
    #    sgx-pck-id-retrieval-tool
    sgx-psw
    #    sgx-ra-service
    sgx-sdk
    sgx-ssl
    #    tdx-qgs
  ];

}
