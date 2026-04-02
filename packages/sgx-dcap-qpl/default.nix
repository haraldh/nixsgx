{
  lib,
  stdenv,
  fetchFromGitHub,
  openssl,
  curl,
}:
let
  version = "1.25";

  dcapSrc = fetchFromGitHub {
    owner = "intel";
    repo = "confidential-computing.tee.dcap";
    rev = "DCAP_${version}";
    hash = "sha256-EXfQ1nOt8IP09N4yKUeQmlbAbr/4FXoToAnBNcQb2dM=";
    fetchSubmodules = true;
  };

  sgxSdkSrc = fetchFromGitHub {
    owner = "intel";
    repo = "confidential-computing.sgx";
    rev = "sgx_2.28";
    hash = "sha256-t/pU+8VGnyKQ1tKvOihgCWWOt/dcjntBtKCRGwYkydo=";
    fetchSubmodules = false;
  };
in
stdenv.mkDerivation {
  pname = "sgx-dcap-qpl";
  inherit version;

  src = dcapSrc;

  buildInputs = [
    openssl
    curl
  ];

  postPatch = ''
    patchShebangs --build $(find . -name '*.sh')
  ''
  + lib.optionalString stdenv.isDarwin ''
    # se_thread.c: replace Linux syscall(__NR_gettid) with pthread_threadid_np
    substituteInPlace QuoteGeneration/common/src/se_thread.c \
      --replace-fail \
        'unsigned int se_get_threadid(void) { return (unsigned)syscall(__NR_gettid);}' \
        '#ifdef __APPLE__
    #include <pthread.h>
    unsigned int se_get_threadid(void) { uint64_t tid; pthread_threadid_np(NULL, &tid); return (unsigned)tid; }
    #else
    unsigned int se_get_threadid(void) { return (unsigned)syscall(__NR_gettid); }
    #endif'

    # network_wrapper.cpp: RTLD_DEEPBIND is Linux-only, use .dylib for libcurl
    substituteInPlace QuoteGeneration/qcnl/linux/network_wrapper.cpp \
      --replace-fail 'RTLD_LAZY | RTLD_DEEPBIND' 'RTLD_LAZY' \
      --replace-fail '"libcurl.so"' '"libcurl.dylib"'
  '';

  buildPhase = ''
    runHook preBuild

    # --- Directories ---
    export DCAP_SRC=$PWD
    export SGX_SDK_SRC=${sgxSdkSrc}
    export OPENSSL_INC=${openssl.dev}/include
    export OPENSSL_LIB=${lib.getLib openssl}/lib
    export CURL_INC=${curl.dev}/include

    # --- Create a fake SGX SDK layout with just the headers ---
    export SGX_SDK=$TMPDIR/sgx-sdk
    mkdir -p $SGX_SDK/include/internal
    cp -r $SGX_SDK_SRC/common/inc/*.h $SGX_SDK/include/
    cp -r $SGX_SDK_SRC/common/inc/internal/*.h $SGX_SDK/include/internal/

    # --- Create a fake prebuilt OpenSSL layout ---
    export PREBUILD_OPENSSL=$TMPDIR/prebuilt-openssl
    mkdir -p $PREBUILD_OPENSSL/inc $PREBUILD_OPENSSL/lib/linux64
    ln -s $OPENSSL_INC/openssl $PREBUILD_OPENSSL/inc/openssl
    ln -s $OPENSSL_LIB/libcrypto.a $PREBUILD_OPENSSL/lib/linux64/libcrypto.a \
      || ln -s $OPENSSL_LIB/libcrypto${
        if stdenv.isDarwin then ".dylib" else ".so"
      } $PREBUILD_OPENSSL/lib/linux64/libcrypto${if stdenv.isDarwin then ".dylib" else ".so"}

    # --- Determine version strings ---
    SGX_VER=$(awk '/#define STRFILEVER/ { gsub(/"/, "", $3); print $3 }' \
      QuoteGeneration/common/inc/internal/se_version.h)
    SGX_MAJOR_VER=$(echo $SGX_VER | cut -d. -f1)

    # --- Common flags ---
    COMMON_FLAGS="-O2 -ffunction-sections -fdata-sections -fstack-protector-strong"
    COMMON_FLAGS="$COMMON_FLAGS -DNDEBUG -DDISABLE_TRACE"
    COMMON_FLAGS="$COMMON_FLAGS -Wall -Wextra -fPIC"
  ''
  + (
    if stdenv.isDarwin then
      ''
        COMMON_LDFLAGS=""
      ''
    else
      ''
        COMMON_LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack"
      ''
  )
  + ''

    CXXFLAGS_COMMON="$COMMON_FLAGS -std=c++14 -Wno-attributes"

    # Include paths
    QG_DIR=$DCAP_SRC/QuoteGeneration
    QV_DIR=$DCAP_SRC/QuoteVerification
    QVL_SRC=$QV_DIR/QVL/Src
    PCKCERT_DIR=$DCAP_SRC/tools/PCKCertSelection

    # ===================================================================
    # 1. Build PCKCertSelection static library
    # ===================================================================
    echo "Building PCKCertSelection..."

    PCKCERT_INC="-I$PCKCERT_DIR/PCKCertSelectionLib \
      -I$PCKCERT_DIR/include \
      -I$PREBUILD_OPENSSL/inc \
      -I$QVL_SRC/ThirdParty/rapidjson/include \
      -I$QVL_SRC/AttestationParsers/include \
      -I$QVL_SRC/AttestationCommons/include \
      -I$QVL_SRC/AttestationParsers/src \
      -I$QG_DIR/common/inc/internal \
      -I$QVL_SRC/AttestationCommons/include/Utils"
    PCKCERT_FLAGS="$CXXFLAGS_COMMON $PCKCERT_INC -DPCK_CERT_SELECTION_WITH_COMPONENT -fvisibility=hidden"

    mkdir -p $TMPDIR/pckcert

    # Local sources
    for src in pck_sorter.cpp pck_cert_selection.cpp config_selector.cpp tcb_manager.cpp; do
      $CXX $PCKCERT_FLAGS -c $PCKCERT_DIR/PCKCertSelectionLib/$src -o $TMPDIR/pckcert/$(basename $src .cpp).o
    done

    # QVL Attestation Parser sources
    for src in $QVL_SRC/AttestationParsers/src/ParserUtils.cpp; do
      $CXX $PCKCERT_FLAGS -c $src -o $TMPDIR/pckcert/$(basename $src .cpp).o
    done
    for src in Certificate.cpp DistinguishedName.cpp Extension.cpp PckCertificate.cpp Signature.cpp Tcb.cpp Validity.cpp; do
      $CXX $PCKCERT_FLAGS -c $QVL_SRC/AttestationParsers/src/X509/$src -o $TMPDIR/pckcert/$(basename $src .cpp).o
    done
    $CXX $PCKCERT_FLAGS -c $QVL_SRC/AttestationParsers/src/OpensslHelpers/OidUtils.cpp -o $TMPDIR/pckcert/OidUtils.o
    for src in JsonParser.cpp TcbInfo.cpp TcbLevel.cpp TdxModule.cpp TcbComponent.cpp TdxModuleTcb.cpp TdxModuleTcbLevel.cpp TdxModuleIdentity.cpp; do
      $CXX $PCKCERT_FLAGS -c $QVL_SRC/AttestationParsers/src/Json/$src -o $TMPDIR/pckcert/$(basename $src .cpp).o
    done
    for src in GMTime.cpp TimeUtils.cpp; do
      $CXX $PCKCERT_FLAGS -c $QVL_SRC/AttestationCommons/src/Utils/$src -o $TMPDIR/pckcert/$(basename $src .cpp).o
    done

    $AR rsD $TMPDIR/libPCKCertSelection.a $TMPDIR/pckcert/*.o

    # ===================================================================
    # 2. Build QCNL (libsgx_default_qcnl_wrapper)
    # ===================================================================
    echo "Building QCNL..."

    QCNL_INC="-I$QG_DIR/quote_wrapper/common/inc \
      -I$QG_DIR/qcnl/inc \
      -I$SGX_SDK/include \
      -I$QG_DIR/common/inc/internal \
      -I$QG_DIR/pce_wrapper/inc \
      -I$QV_DIR/QVL/Src/ThirdParty/rapidjson/include/rapidjson \
      -I$PCKCERT_DIR/include \
      -I$PREBUILD_OPENSSL/inc \
      -I$CURL_INC"

    mkdir -p $TMPDIR/qcnl

    # C++ sources (platform-agnostic)
    for src in sgx_default_qcnl_wrapper.cpp certification_provider.cpp \
               certification_service.cpp qcnl_config.cpp qcnl_util.cpp \
               pccs_response_object.cpp; do
      $CXX $CXXFLAGS_COMMON $QCNL_INC -c $QG_DIR/qcnl/$src -o $TMPDIR/qcnl/$(basename $src .cpp).o
    done

    # C++ sources (linux/ dir — used on both Linux and Darwin)
    for src in network_wrapper.cpp qcnl_config_impl.cpp; do
      $CXX $CXXFLAGS_COMMON $QCNL_INC -c $QG_DIR/qcnl/linux/$src -o $TMPDIR/qcnl/$(basename $src .cpp).o
    done

    # C sources
    $CC $COMMON_FLAGS -fPIC $QCNL_INC -c $QG_DIR/common/src/se_thread.c -o $TMPDIR/qcnl/se_thread.o

    # Link QCNL shared library
  ''
  + (
    if stdenv.isDarwin then
      ''
        $CXX $CXXFLAGS_COMMON \
          $TMPDIR/qcnl/*.o \
          $TMPDIR/libPCKCertSelection.a \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -dynamiclib -Wl,-install_name,$out/lib/libsgx_default_qcnl_wrapper.$SGX_MAJOR_VER.dylib \
          -Wl,-exported_symbols_list,${./sgx_default_qcnl.exported} \
          -Wl,-dead_strip \
          -pthread \
          -o $TMPDIR/libsgx_default_qcnl_wrapper.dylib
      ''
    else
      ''
        $CXX $CXXFLAGS_COMMON \
          $TMPDIR/qcnl/*.o \
          $TMPDIR/libPCKCertSelection.a \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -shared -Wl,-soname=libsgx_default_qcnl_wrapper.so.$SGX_MAJOR_VER \
          -Wl,--version-script=$QG_DIR/qcnl/linux/sgx_default_qcnl.lds \
          -Wl,--gc-sections \
          $COMMON_LDFLAGS \
          -pthread -ldl \
          -o $TMPDIR/libsgx_default_qcnl_wrapper.so
      ''
  )
  + ''

    # ===================================================================
    # 3. Build QPL (libdcap_quoteprov)
    # ===================================================================
    echo "Building QPL..."

    QPL_INC="-I$QG_DIR/quote_wrapper/common/inc \
      -I$QG_DIR/qpl/inc \
      -I$SGX_SDK/include \
      -I$QG_DIR/common/inc/internal \
      -I$QG_DIR/qcnl/inc \
      -I$PREBUILD_OPENSSL/inc"

    mkdir -p $TMPDIR/qpl

    # C++ sources
    for src in sgx_default_quote_provider.cpp sgx_base64.cpp; do
      $CXX $CXXFLAGS_COMMON $QPL_INC -c $QG_DIR/qpl/$src -o $TMPDIR/qpl/$(basename $src .cpp).o
    done
    $CXX $CXXFLAGS_COMMON $QPL_INC -c $QG_DIR/qpl/linux/x509.cpp -o $TMPDIR/qpl/x509.o

    # Link QPL shared library
  ''
  + (
    if stdenv.isDarwin then
      ''
        $CXX $CXXFLAGS_COMMON \
          $TMPDIR/qpl/*.o \
          -L$TMPDIR -lsgx_default_qcnl_wrapper \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -dynamiclib -Wl,-install_name,$out/lib/libdcap_quoteprov.$SGX_MAJOR_VER.dylib \
          -Wl,-exported_symbols_list,${./sgx_default_quote_provider.exported} \
          -Wl,-dead_strip \
          -pthread \
          -o $TMPDIR/libdcap_quoteprov.dylib
      ''
    else
      ''
        $CXX $CXXFLAGS_COMMON \
          $TMPDIR/qpl/*.o \
          -L$TMPDIR -lsgx_default_qcnl_wrapper \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -shared -Wl,-soname=libdcap_quoteprov.so.$SGX_MAJOR_VER \
          -Wl,--version-script=$QG_DIR/qpl/linux/sgx_default_quote_provider.lds \
          -Wl,--gc-sections \
          $COMMON_LDFLAGS \
          -pthread -ldl \
          -o $TMPDIR/libdcap_quoteprov.so
      ''
  )
  + ''

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    SGX_VER=$(awk '/#define STRFILEVER/ { gsub(/"/, "", $3); print $3 }' \
      QuoteGeneration/common/inc/internal/se_version.h)
    SGX_MAJOR_VER=$(echo $SGX_VER | cut -d. -f1)

    mkdir -p $out/lib $out/include

  ''
  + (
    if stdenv.isDarwin then
      ''
        # QCNL
        cp $TMPDIR/libsgx_default_qcnl_wrapper.dylib $out/lib/libsgx_default_qcnl_wrapper.$SGX_VER.dylib
        ln -s libsgx_default_qcnl_wrapper.$SGX_VER.dylib $out/lib/libsgx_default_qcnl_wrapper.$SGX_MAJOR_VER.dylib
        ln -s libsgx_default_qcnl_wrapper.$SGX_MAJOR_VER.dylib $out/lib/libsgx_default_qcnl_wrapper.dylib

        # QPL
        cp $TMPDIR/libdcap_quoteprov.dylib $out/lib/libdcap_quoteprov.$SGX_VER.dylib
        ln -s libdcap_quoteprov.$SGX_VER.dylib $out/lib/libdcap_quoteprov.$SGX_MAJOR_VER.dylib
        ln -s libdcap_quoteprov.$SGX_MAJOR_VER.dylib $out/lib/libdcap_quoteprov.dylib
      ''
    else
      ''
        # QCNL
        cp $TMPDIR/libsgx_default_qcnl_wrapper.so $out/lib/libsgx_default_qcnl_wrapper.so.$SGX_VER
        ln -s libsgx_default_qcnl_wrapper.so.$SGX_VER $out/lib/libsgx_default_qcnl_wrapper.so.$SGX_MAJOR_VER
        ln -s libsgx_default_qcnl_wrapper.so.$SGX_MAJOR_VER $out/lib/libsgx_default_qcnl_wrapper.so

        # QPL
        cp $TMPDIR/libdcap_quoteprov.so $out/lib/libdcap_quoteprov.so.$SGX_VER
        ln -s libdcap_quoteprov.so.$SGX_VER $out/lib/libdcap_quoteprov.so.$SGX_MAJOR_VER
        ln -s libdcap_quoteprov.so.$SGX_MAJOR_VER $out/lib/libdcap_quoteprov.so
      ''
  )
  + ''

    # Install public headers
    cp $QG_DIR/qpl/inc/sgx_default_quote_provider.h $out/include/
    cp $QG_DIR/qcnl/inc/sgx_default_qcnl_wrapper.h $out/include/

    runHook postInstall
  '';

  dontUseCmakeConfigure = true;
  doCheck = false;

  meta = with lib; {
    description = "Intel(R) SGX DCAP Quote Provider Library (QPL)";
    homepage = "https://github.com/intel/confidential-computing.tee.dcap";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    license = with licenses; [ bsd3 ];
  };
}
