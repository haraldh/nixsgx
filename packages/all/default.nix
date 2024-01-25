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
    sgx-dcap
    sgx-psw
    sgx-sdk
    sgx-ssl
    # docker-gramine-azure
    # docker-gramine-dcap
    restart-aesmd
    protobufc
  ];

}
