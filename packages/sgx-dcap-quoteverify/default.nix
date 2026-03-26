{
  lib,
  stdenv,
  fetchFromGitHub,
  openssl,
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
    hash = "sha256-dRLTyIMNHnPmHb+ro2O7UtzR5EkhMXvxR5BKa6kfNhs=";
    fetchSubmodules = false;
  };
in
stdenv.mkDerivation {
  pname = "sgx-dcap-quoteverify";
  inherit version;

  src = dcapSrc;

  buildInputs = [
    openssl
  ];

  postPatch = ''
    patchShebangs --build $(find . -name '*.sh')
  '';

  buildPhase = ''
    runHook preBuild

    # --- Directories ---
    export DCAP_SRC=$PWD
    export SGX_SDK_SRC=${sgxSdkSrc}
    export OPENSSL_INC=${openssl.dev}/include
    export OPENSSL_LIB=${lib.getLib openssl}/lib

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
      || ln -s $OPENSSL_LIB/libcrypto.so $PREBUILD_OPENSSL/lib/linux64/libcrypto.so

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
    COMMON_LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack"

    # Include paths
    QG_DIR=$DCAP_SRC/QuoteGeneration
    QV_DIR=$DCAP_SRC/QuoteVerification
    QVL_SRC=$QV_DIR/QVL/Src
    QVE_SRC=$DCAP_SRC/ae/QvE
    EXTERNAL_DIR=$DCAP_SRC/external

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

    CFLAGS_COMMON="$COMMON_FLAGS -Wjump-misses-init -Wstrict-prototypes -Wunsuffixed-float-constants"
    CXXFLAGS_COMMON="$COMMON_FLAGS -Wnon-virtual-dtor -std=c++17"

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
    echo "Building libsgx_dcap_quoteverify.so..."
    QV_LINUX=$QV_DIR/dcap_quoteverify/linux
    VERIFY_OBJS=""

    # C++ sources from dcap_quoteverify/ and dcap_quoteverify/linux/
    for src in $(find $QV_DIR/dcap_quoteverify -maxdepth 1 -name '*.cpp' | sort) \
               $(find $QV_LINUX -maxdepth 1 -name '*.cpp' | sort); do
      obj=$TMPDIR/qv/$(basename $src .cpp).o
      mkdir -p $TMPDIR/qv
      $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $src -o $obj
      VERIFY_OBJS="$VERIFY_OBJS $obj"
    done

    # C sources
    COMMON_DIR=$QG_DIR/common
    $CC $CFLAGS_COMMON $QVL_VERIFY_INC -c $COMMON_DIR/src/se_trace.c -o $TMPDIR/qv/se_trace.o
    $CC $CFLAGS_COMMON $QVL_VERIFY_INC -c $COMMON_DIR/src/se_thread.c -o $TMPDIR/qv/se_thread.o
    $CC $CFLAGS_COMMON $QVL_VERIFY_INC -c $QV_LINUX/qve_u.c -o $TMPDIR/qv/qve_u.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/se_trace.o $TMPDIR/qv/se_thread.o $TMPDIR/qv/qve_u.o"

    # QvE untrusted wrapper objects
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QVE_SRC/qve/qve.cpp -o $TMPDIR/qv/untrusted_qve.o
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QVE_SRC/qve/qve_logic.cpp -o $TMPDIR/qv/untrusted_qve_logic.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/untrusted_qve.o $TMPDIR/qv/untrusted_qve_logic.o"

    # Common lib objects
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QG_DIR/qpl/sgx_base64.cpp -o $TMPDIR/qv/sgx_base64.o
    $CXX $CXXFLAGS_COMMON $QVL_VERIFY_INC -c $QV_DIR/appraisal/common/ec_key.cpp -o $TMPDIR/qv/ec_key.o
    VERIFY_OBJS="$VERIFY_OBJS $TMPDIR/qv/sgx_base64.o $TMPDIR/qv/ec_key.o"

    # Link everything
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

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    SGX_VER=$(awk '/#define STRFILEVER/ { gsub(/"/, "", $3); print $3 }' \
      QuoteGeneration/common/inc/internal/se_version.h)
    SGX_MAJOR_VER=$(echo $SGX_VER | cut -d. -f1)

    mkdir -p $out/lib $out/include

    cp $TMPDIR/libsgx_dcap_quoteverify.so $out/lib/libsgx_dcap_quoteverify.so.$SGX_VER
    ln -s libsgx_dcap_quoteverify.so.$SGX_VER $out/lib/libsgx_dcap_quoteverify.so.$SGX_MAJOR_VER
    ln -s libsgx_dcap_quoteverify.so.$SGX_MAJOR_VER $out/lib/libsgx_dcap_quoteverify.so

    # Install public headers
    cp QuoteVerification/dcap_quoteverify/inc/sgx_dcap_quoteverify.h $out/include/
    cp QuoteGeneration/quote_wrapper/common/inc/sgx_ql_quote.h $out/include/
    cp ae/QvE/Include/sgx_qve_header.h $out/include/
    cp ae/QvE/Include/sgx_qve_def.h $out/include/

    runHook postInstall
  '';

  dontUseCmakeConfigure = true;
  doCheck = false;

  meta = with lib; {
    description = "Intel(R) SGX DCAP Quote Verification Library";
    homepage = "https://github.com/intel/confidential-computing.tee.dcap";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    license = with licenses; [ bsd3 ];
  };
}
