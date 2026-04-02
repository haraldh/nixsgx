# Portable (non-x86) build of sgx-dcap: only quote_verify and default_qpl outputs.
# These are software-only (QVL) libraries that do not require SGX hardware.
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

  soExt = if stdenv.isDarwin then "dylib" else "so";
in
stdenv.mkDerivation {
  pname = "sgx-dcap";
  inherit version;

  src = dcapSrc;

  outputs = [
    "out"
    "quote_verify"
    "default_qpl"
  ];

  buildInputs = [
    openssl
    curl
  ];

  patches = [
    ./SGXDataCenterAttestationPrimitives-sgx_default_qcnl_conf.patch
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

    # config.cpp: use .dylib for the QPL on macOS
    substituteInPlace QuoteVerification/dcap_quoteverify/linux/config.cpp \
      --replace-fail '"libdcap_quoteprov.so.1"' '"libdcap_quoteprov.dylib"' \
      --replace-fail '"libdcap_quoteprov.so"' '"libdcap_quoteprov.dylib"'

    # qve_parser.cpp: guard /proc/self/exe with __linux__
    substituteInPlace QuoteVerification/dcap_quoteverify/linux/qve_parser.cpp \
      --replace-fail \
        'ssize_t i = readlink( "/proc/self/exe", p_file_path, buf_size - 1);' \
        '#ifdef __linux__
            ssize_t i = readlink( "/proc/self/exe", p_file_path, buf_size - 1);
    #else
            ssize_t i = -1;
    #endif'

    # network_wrapper.cpp: RTLD_DEEPBIND is Linux-only, use absolute path for libcurl
    substituteInPlace QuoteGeneration/qcnl/linux/network_wrapper.cpp \
      --replace-fail 'RTLD_LAZY | RTLD_DEEPBIND' 'RTLD_LAZY' \
      --replace-fail '"libcurl.so"' '"${lib.getLib curl}/lib/libcurl.${soExt}"'
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

    # --- Create a fake SGXSSL layout ---
    export SGXSSL_PACKAGE_PATH=$TMPDIR/sgxssl
    mkdir -p $SGXSSL_PACKAGE_PATH/lib64
    $CC -c -fPIC ${./sgxssl_stub.c} -o $TMPDIR/sgxssl_stub.o
    $AR rsD $SGXSSL_PACKAGE_PATH/lib64/libsgx_usgxssl.a $TMPDIR/sgxssl_stub.o

    # --- Create a fake prebuilt OpenSSL layout ---
    export PREBUILD_OPENSSL=$TMPDIR/prebuilt-openssl
    mkdir -p $PREBUILD_OPENSSL/inc $PREBUILD_OPENSSL/lib/linux64
    ln -s $OPENSSL_INC/openssl $PREBUILD_OPENSSL/inc/openssl
    ln -s $OPENSSL_LIB/libcrypto.a $PREBUILD_OPENSSL/lib/linux64/libcrypto.a \
      || ln -s $OPENSSL_LIB/libcrypto.${soExt} $PREBUILD_OPENSSL/lib/linux64/libcrypto.${soExt}

    # --- Copy pre-generated edger8r files ---
    cp ${./qve_u.c} QuoteVerification/dcap_quoteverify/linux/qve_u.c
    cp ${./qve_u.h} QuoteVerification/dcap_quoteverify/linux/qve_u.h

    # --- Determine version strings ---
    SGX_VER=$(awk '/#define STRFILEVER/ { gsub(/"/, "", $3); print $3 }' \
      QuoteGeneration/common/inc/internal/se_version.h)
    SGX_MAJOR_VER=$(echo $SGX_VER | cut -d. -f1)

    # --- Common flags ---
    COMMON_FLAGS="-O2 -ffunction-sections -fdata-sections -fstack-protector-strong"
    COMMON_FLAGS="$COMMON_FLAGS -D_GLIBCXX_ASSERTIONS -DNDEBUG"
    COMMON_FLAGS="$COMMON_FLAGS -Wall -Wextra -fPIC -USGX_TRUSTED"
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

    # Include paths
    QG_DIR=$DCAP_SRC/QuoteGeneration
    QV_DIR=$DCAP_SRC/QuoteVerification
    QVL_SRC=$QV_DIR/QVL/Src
    QVE_SRC=$DCAP_SRC/ae/QvE
    EXTERNAL_DIR=$DCAP_SRC/external
    PCKCERT_DIR=$DCAP_SRC/tools/PCKCertSelection

    QVL_LIB_PATH=$QVL_SRC/AttestationLibrary
    QVL_PARSER_PATH=$QVL_SRC/AttestationParsers
    QVL_COMMON_PATH=$QVL_SRC/AttestationCommons

    QVL_LIB_INC="-I$QVL_COMMON_PATH/include -I$QVL_COMMON_PATH/include/Utils \
      -I$QVL_LIB_PATH/include -I$QVL_LIB_PATH/src \
      -I$QVL_PARSER_PATH/include -I$QVL_SRC/ThirdParty/rapidjson/include \
      -isystem$EXTERNAL_DIR/jwt-cpp/include \
      -I$PREBUILD_OPENSSL/inc -I$QVE_SRC/Include"

    QVL_PARSER_INC="-I$QVL_COMMON_PATH/include -I$QVL_COMMON_PATH/include/Utils \
      -I$QVL_SRC -I$QVL_PARSER_PATH/include -I$QVL_PARSER_PATH/src \
      -I$QVL_LIB_PATH/include \
      -isystem$QVL_SRC/ThirdParty/rapidjson/include \
      -I$PREBUILD_OPENSSL/inc"

    QVL_VERIFY_INC="-I$QVE_SRC/Include \
      -I$QV_DIR/dcap_quoteverify/inc \
      -I$QG_DIR/quote_wrapper/common/inc \
      -I$SGX_SDK/include \
      -I$QG_DIR/common/inc/internal \
      -I$QG_DIR/common/inc/internal/linux \
      -I$QG_DIR/pce_wrapper/inc \
      -I$PREBUILD_OPENSSL/inc \
      $QVL_LIB_INC \
      -I$QG_DIR/qpl/inc \
      -I$QV_DIR/appraisal/common \
      -I$QV_DIR/appraisal/qal"

  ''
  + (
    if stdenv.isDarwin then
      ''
        CFLAGS_COMMON="$COMMON_FLAGS"
      ''
    else
      ''
        CFLAGS_COMMON="$COMMON_FLAGS -Wjump-misses-init -Wstrict-prototypes -Wunsuffixed-float-constants"
      ''
  )
  + ''
    CXXFLAGS_COMMON="$COMMON_FLAGS -Wnon-virtual-dtor -std=c++17"
    CXXFLAGS_QPL="$COMMON_FLAGS -DDISABLE_TRACE -Wno-attributes -std=c++14"

    # ===================================================================
    # 1. Build quoteverify (libsgx_dcap_quoteverify)
    # ===================================================================

    # --- Build QVL Attestation Library (untrusted) ---
    echo "Building QVL AttestationLibrary..."
    QVL_LIB_FILES=$(find $QVL_LIB_PATH/src -name '*.cpp' | sort)
    QVL_COMMON_FILES=$(find $QVL_COMMON_PATH/src/Utils -name '*.cpp' | sort)
    QVL_LIB_OBJS=""
    for src in $QVL_LIB_FILES $QVL_COMMON_FILES; do
      obj=$TMPDIR/qvl_lib/$(basename $src .cpp)_untrusted.o
      mkdir -p $TMPDIR/qvl_lib
      $CXX $CXXFLAGS_COMMON $QVL_LIB_INC -c $src -o $obj
      QVL_LIB_OBJS="$QVL_LIB_OBJS $obj"
    done
    $AR rsD $TMPDIR/libsgx_dcap_qvl_parser.a $QVL_LIB_OBJS

    # --- Build QVL Attestation Parsers (untrusted) ---
    echo "Building QVL AttestationParsers..."
    QVL_PARSER_FILES=$(find $QVL_PARSER_PATH/src -name '*.cpp' | sort)
    QVL_PARSER_OBJS=""
    for src in $QVL_PARSER_FILES; do
      obj=$TMPDIR/qvl_parser/$(basename $src .cpp)_untrusted.o
      mkdir -p $TMPDIR/qvl_parser
      $CXX $CXXFLAGS_COMMON $QVL_PARSER_INC -c $src -o $obj
      QVL_PARSER_OBJS="$QVL_PARSER_OBJS $obj"
    done
    $AR rsD $TMPDIR/libsgx_dcap_qvl_attestation.a $QVL_PARSER_OBJS

    # --- Build quoteverify library ---
    echo "Building libsgx_dcap_quoteverify..."
    QV_LINUX=$QV_DIR/dcap_quoteverify/linux
    VERIFY_OBJS=""

    for src in $(find $QV_DIR/dcap_quoteverify -maxdepth 1 -name '*.cpp' | sort) \
               $(find $QV_LINUX -maxdepth 1 -name '*.cpp' | sort); do
      obj=$TMPDIR/qv/$(basename $src .cpp).o
      mkdir -p $TMPDIR/qv
      $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $src -o $obj
      VERIFY_OBJS="$VERIFY_OBJS $obj"
    done

    COMMON_DIR=$QG_DIR/common
    $CC $CFLAGS_COMMON $QVL_VERIFY_INC -c $COMMON_DIR/src/se_trace.c -o $TMPDIR/qv/se_trace.o
    $CC $CFLAGS_COMMON $QVL_VERIFY_INC -c $COMMON_DIR/src/se_thread.c -o $TMPDIR/qv/se_thread.o
    $CC $CFLAGS_COMMON $QVL_VERIFY_INC -c $QV_LINUX/qve_u.c -o $TMPDIR/qv/qve_u.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/se_trace.o $TMPDIR/qv/se_thread.o $TMPDIR/qv/qve_u.o"

    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -Wno-tautological-constant-out-of-range-compare -c $QVE_SRC/qve/qve.cpp -o $TMPDIR/qv/untrusted_qve.o
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QVE_SRC/qve/qve_logic.cpp -o $TMPDIR/qv/untrusted_qve_logic.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/untrusted_qve.o $TMPDIR/qv/untrusted_qve_logic.o"

    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QG_DIR/qpl/sgx_base64.cpp -o $TMPDIR/qv/sgx_base64.o
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QV_DIR/appraisal/common/ec_key.cpp -o $TMPDIR/qv/ec_key.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/sgx_base64.o $TMPDIR/qv/ec_key.o"

    # QAL stub — tee_qae_get_target_info is in the QAL which we don't build.
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c ${./qal_stub.cpp} -o $TMPDIR/qv/qal_stub.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/qal_stub.o"

  ''
  + (
    if stdenv.isDarwin then
      ''
        $CXX $CXXFLAGS_COMMON \
          $VERIFY_OBJS \
          -L$SGXSSL_PACKAGE_PATH/lib64 -lsgx_usgxssl \
          -L$TMPDIR -lsgx_dcap_qvl_parser -lsgx_dcap_qvl_attestation \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -dynamiclib -Wl,-install_name,$quote_verify/lib/libsgx_dcap_quoteverify.$SGX_MAJOR_VER.dylib \
          -Wl,-exported_symbols_list,${./sgx_dcap_quoteverify.exported} \
          -Wl,-dead_strip \
          -pthread \
          -o $TMPDIR/libsgx_dcap_quoteverify.dylib
      ''
    else
      ''
        $CXX $CXXFLAGS_COMMON \
          $VERIFY_OBJS \
          -L$SGXSSL_PACKAGE_PATH/lib64 -lsgx_usgxssl \
          -L$TMPDIR -lsgx_dcap_qvl_parser -lsgx_dcap_qvl_attestation \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -shared -Wl,-soname=libsgx_dcap_quoteverify.so.$SGX_MAJOR_VER \
          -Wl,--version-script=$QV_LINUX/sgx_dcap_quoteverify.lds \
          -Wl,--gc-sections \
          $COMMON_LDFLAGS \
          -pthread -ldl \
          -o $TMPDIR/libsgx_dcap_quoteverify.so
      ''
  )
  + ''

    # ===================================================================
    # 2. Build QPL (PCKCertSelection + QCNL + libdcap_quoteprov)
    # ===================================================================

    # --- PCKCertSelection static library ---
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
    PCKCERT_FLAGS="$CXXFLAGS_QPL $PCKCERT_INC -DPCK_CERT_SELECTION_WITH_COMPONENT -fvisibility=hidden"

    mkdir -p $TMPDIR/pckcert
    for src in pck_sorter.cpp pck_cert_selection.cpp config_selector.cpp tcb_manager.cpp; do
      $CXX $PCKCERT_FLAGS -c $PCKCERT_DIR/PCKCertSelectionLib/$src -o $TMPDIR/pckcert/$(basename $src .cpp).o
    done
    $CXX $PCKCERT_FLAGS -c $QVL_SRC/AttestationParsers/src/ParserUtils.cpp -o $TMPDIR/pckcert/ParserUtils.o
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

    # --- QCNL (libsgx_default_qcnl_wrapper) ---
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
    for src in sgx_default_qcnl_wrapper.cpp certification_provider.cpp \
               certification_service.cpp qcnl_config.cpp qcnl_util.cpp \
               pccs_response_object.cpp; do
      $CXX $CXXFLAGS_QPL $QCNL_INC -c $QG_DIR/qcnl/$src -o $TMPDIR/qcnl/$(basename $src .cpp).o
    done
    for src in network_wrapper.cpp qcnl_config_impl.cpp; do
      $CXX $CXXFLAGS_QPL $QCNL_INC -c $QG_DIR/qcnl/linux/$src -o $TMPDIR/qcnl/$(basename $src .cpp).o
    done
    $CC $COMMON_FLAGS -fPIC $QCNL_INC -c $QG_DIR/common/src/se_thread.c -o $TMPDIR/qcnl/se_thread.o

  ''
  + (
    if stdenv.isDarwin then
      ''
        $CXX $CXXFLAGS_QPL \
          $TMPDIR/qcnl/*.o \
          $TMPDIR/libPCKCertSelection.a \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -dynamiclib -Wl,-install_name,$default_qpl/lib/libsgx_default_qcnl_wrapper.$SGX_MAJOR_VER.dylib \
          -Wl,-exported_symbols_list,${./sgx_default_qcnl.exported} \
          -Wl,-dead_strip \
          -pthread \
          -o $TMPDIR/libsgx_default_qcnl_wrapper.dylib
      ''
    else
      ''
        $CXX $CXXFLAGS_QPL \
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

    # --- QPL (libdcap_quoteprov) ---
    echo "Building QPL..."

    QPL_INC="-I$QG_DIR/quote_wrapper/common/inc \
      -I$QG_DIR/qpl/inc \
      -I$SGX_SDK/include \
      -I$QG_DIR/common/inc/internal \
      -I$QG_DIR/qcnl/inc \
      -I$PREBUILD_OPENSSL/inc"

    mkdir -p $TMPDIR/qpl
    for src in sgx_default_quote_provider.cpp sgx_base64.cpp; do
      $CXX $CXXFLAGS_QPL $QPL_INC -c $QG_DIR/qpl/$src -o $TMPDIR/qpl/$(basename $src .cpp).o
    done
    $CXX $CXXFLAGS_QPL $QPL_INC -c $QG_DIR/qpl/linux/x509.cpp -o $TMPDIR/qpl/x509.o

  ''
  + (
    if stdenv.isDarwin then
      ''
        $CXX $CXXFLAGS_QPL \
          $TMPDIR/qpl/*.o \
          -L$TMPDIR -lsgx_default_qcnl_wrapper \
          -L$PREBUILD_OPENSSL/lib/linux64 -lcrypto \
          -dynamiclib -Wl,-install_name,$default_qpl/lib/libdcap_quoteprov.$SGX_MAJOR_VER.dylib \
          -Wl,-exported_symbols_list,${./sgx_default_quote_provider.exported} \
          -Wl,-dead_strip \
          -pthread \
          -o $TMPDIR/libdcap_quoteprov.dylib
      ''
    else
      ''
        $CXX $CXXFLAGS_QPL \
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

    # --- quote_verify output ---
    mkdir -p $quote_verify/lib $quote_verify/include
  ''
  + (
    if stdenv.isDarwin then
      ''
        cp $TMPDIR/libsgx_dcap_quoteverify.dylib $quote_verify/lib/libsgx_dcap_quoteverify.$SGX_VER.dylib
        ln -s libsgx_dcap_quoteverify.$SGX_VER.dylib $quote_verify/lib/libsgx_dcap_quoteverify.$SGX_MAJOR_VER.dylib
        ln -s libsgx_dcap_quoteverify.$SGX_MAJOR_VER.dylib $quote_verify/lib/libsgx_dcap_quoteverify.dylib
      ''
    else
      ''
        cp $TMPDIR/libsgx_dcap_quoteverify.so $quote_verify/lib/libsgx_dcap_quoteverify.so.$SGX_VER
        ln -s libsgx_dcap_quoteverify.so.$SGX_VER $quote_verify/lib/libsgx_dcap_quoteverify.so.$SGX_MAJOR_VER
        ln -s libsgx_dcap_quoteverify.so.$SGX_MAJOR_VER $quote_verify/lib/libsgx_dcap_quoteverify.so
      ''
  )
  + ''

    cp QuoteVerification/dcap_quoteverify/inc/sgx_dcap_quoteverify.h $quote_verify/include/
    cp QuoteGeneration/quote_wrapper/common/inc/sgx_ql_quote.h $quote_verify/include/
    cp QuoteGeneration/quote_wrapper/common/inc/sgx_ql_lib_common.h $quote_verify/include/
    cp QuoteGeneration/quote_wrapper/common/inc/sgx_quote_3.h $quote_verify/include/
    cp ae/QvE/Include/sgx_qve_header.h $quote_verify/include/
    cp ae/QvE/Include/sgx_qve_def.h $quote_verify/include/
    for h in sgx_attributes.h sgx_defs.h sgx_key.h sgx_quote.h \
             sgx_report.h sgx_report2.h sgx_eid.h sgx_error.h; do
      cp $SGX_SDK/include/$h $quote_verify/include/
    done
    cp QuoteGeneration/pce_wrapper/inc/sgx_pce.h $quote_verify/include/

    # --- default_qpl output ---
    mkdir -p $default_qpl/lib
  ''
  + (
    if stdenv.isDarwin then
      ''
        cp $TMPDIR/libsgx_default_qcnl_wrapper.dylib $default_qpl/lib/libsgx_default_qcnl_wrapper.$SGX_VER.dylib
        ln -s libsgx_default_qcnl_wrapper.$SGX_VER.dylib $default_qpl/lib/libsgx_default_qcnl_wrapper.$SGX_MAJOR_VER.dylib
        ln -s libsgx_default_qcnl_wrapper.$SGX_MAJOR_VER.dylib $default_qpl/lib/libsgx_default_qcnl_wrapper.dylib
        cp $TMPDIR/libdcap_quoteprov.dylib $default_qpl/lib/libdcap_quoteprov.$SGX_VER.dylib
        ln -s libdcap_quoteprov.$SGX_VER.dylib $default_qpl/lib/libdcap_quoteprov.$SGX_MAJOR_VER.dylib
        ln -s libdcap_quoteprov.$SGX_MAJOR_VER.dylib $default_qpl/lib/libdcap_quoteprov.dylib
      ''
    else
      ''
        cp $TMPDIR/libsgx_default_qcnl_wrapper.so $default_qpl/lib/libsgx_default_qcnl_wrapper.so.$SGX_VER
        ln -s libsgx_default_qcnl_wrapper.so.$SGX_VER $default_qpl/lib/libsgx_default_qcnl_wrapper.so.$SGX_MAJOR_VER
        ln -s libsgx_default_qcnl_wrapper.so.$SGX_MAJOR_VER $default_qpl/lib/libsgx_default_qcnl_wrapper.so
        cp $TMPDIR/libdcap_quoteprov.so $default_qpl/lib/libdcap_quoteprov.so.$SGX_VER
        ln -s libdcap_quoteprov.so.$SGX_VER $default_qpl/lib/libdcap_quoteprov.so.$SGX_MAJOR_VER
        ln -s libdcap_quoteprov.so.$SGX_MAJOR_VER $default_qpl/lib/libdcap_quoteprov.so
      ''
  )
  + ''

    # Install QCNL config file
    mkdir -p $default_qpl/etc
    cp QuoteGeneration/qcnl/linux/sgx_default_qcnl.conf $default_qpl/etc/

    # --- out (default) output — just a placeholder ---
    mkdir -p $out/share/doc
    echo "sgx-dcap portable build — use quote_verify or default_qpl outputs" > $out/share/doc/README.md

    runHook postInstall
  '';

  dontUseCmakeConfigure = true;
  doCheck = false;

  meta = with lib; {
    description = "Intel(R) SGX DCAP Quote Verification and Provider Libraries (portable)";
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
