{ pkgs
, lib
, nixsgx
, fetchurl
, ...
}:
let
  gcc-wrap = fetchurl {
    url = "https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/gcc-10.2.0.tar.gz";
    hash = "sha256-J+h53MxjnNewzAjtV1wWaUkleVKbU8n/J7C5YmX6hn0=";
  };
  tomlc99-wrap = fetchurl {
    url = "https://github.com/cktan/tomlc99/archive/208203af46bdbdb29ba199660ed78d09c220b6c5.tar.gz";
    hash = "sha256-cxORP94awLCjGjTk/I4QSMDLGwgT59okpEtMw8gPDok=";
  };
  cjson-wrap = fetchurl {
    url = "https://github.com/DaveGamble/cJSON/archive/v1.7.12.tar.gz";
    hash = "sha256-dgaHZlq0Glz/nECxBTwZVyvNqt7xGU5cuhteb4JGhuc=";
  };
  curl-wrap = fetchurl {
    url = "https://curl.se/download/curl-8.4.0.tar.gz";
    hash = "sha256-gW5BgJwEP/KF6MDwanWh+iUCEbv7LcCgN+7vOfGp5Cc=";
  };
  mbedtls-wrap = fetchurl {
    url = "https://github.com/ARMmbed/mbedtls/archive/mbedtls-3.5.0.tar.gz";
    hash = "sha256-AjEfyL0DLYn/mu5TXd21VFgQjcDUxSgGOPxhGup8Xko=";
  };
  uthash-wrap = fetchurl {
    url = "https://github.com/troydhanson/uthash/archive/v2.1.0.tar.gz";
    hash = "sha256-FSzNjmTQ9JU3cjLjlk0Gx+yLuMP70yF/ilcCYU+aZp4=";
  };
  glibc-wrap = fetchurl {
    url = "https://ftp.gnu.org/gnu/glibc/glibc-2.38.tar.gz";
    hash = "sha256-FuUeBFXiiPAzgLQ25B1ZJ8YJRavYbQyYUrhL5X3W7V4=";
  };

  #  python = 
  #    let
  #      overrideAttrs = self: super: {
  #        openssl = super.pkgs.openssl_legacy;
  #        openssl_legacy = super.pkgs.openssl_legacy;
  #      };
  #
  #      packageOverrides = self: super: {
  #        six = super.six.overridePythonAttrs (old: {
  #          pytestFlagsArray = [
  #            # uses ctypes to find native library
  #            "--deselect=test_six.py::test_move_items"
  #          ];
  #        });
  #        freezegun = super.freezegun.overridePythonAttrs (old: {
  #          postUnpack = ''
  #                 rm $sourceRoot/tests/test_sqlite3.py
  #            	  '';
  #          pytestFlagsArray = [
  #            "--deselect=test_sqlite3.py"
  #          ];
  #        });
  #        babel = super.babel.overridePythonAttrs (old: {
  #          doCheck = false;
  #          # nativeCheckInputs = old.nativeCheckInputs ++ [ (super.withPackages (ps: ps.tzdata) ) ];
  #        });
  #      };
  #    in
  #    (pkgs.python3Minimal.overrideAttrs (oldAttrs: rec { 
  #        openssl = oldAttrs.pkgs.openssl_legacy;
  #        openssl_legacy = oldAttrs.pkgs.openssl_legacy;
  #})).override { inherit packageOverrides; inherit overrideAttrs; self = python; };

  python = pkgs.python3;

  my-python-packages = ps: with ps; [
    click
    jinja2
    pyelftools
    tomli
    tomli-w
    cryptography
  ];


in
python.pkgs.buildPythonPackage {
  pname = "gramine";
  version = "1.6";

  src = pkgs.fetchFromGitHub {
    owner = "gramineproject";
    repo = "gramine";
    rev = "v1.6";
    hash = "sha256-LX7/XqxS8z0PomBDqe53sTTYgaXVmP23GSTJMpXRorM=";
    fetchSubmodules = true;
  };

  outputs = [ "out" "dev" ];

  patches = [
    ./meson-options.patch
    ./meson-build.patch
  ];

  # Unpack subproject sources
  postUnpack = ''(
    cd "$sourceRoot/subprojects"
    tar -zxf ${gcc-wrap}
    cp -av packagefiles/gcc-10.2.0/. gcc-10.2.0
    tar -zxf ${tomlc99-wrap}
    cp -av packagefiles/tomlc99/. tomlc99-208203af46bdbdb29ba199660ed78d09c220b6c5
    tar -zxf ${cjson-wrap}
    cp -av packagefiles/cJSON/. cJSON-1.7.12
    tar -zxf ${curl-wrap}
    cp -av packagefiles/curl-8.4.0/. curl-8.4.0
    mkdir mbedtls-mbedtls-3.5.0
    tar -zxf ${mbedtls-wrap} -C mbedtls-mbedtls-3.5.0
    cp -av packagefiles/mbedtls/. mbedtls-mbedtls-3.5.0
    tar -zxf ${uthash-wrap}
    cp -av packagefiles/uthash/. uthash-2.1.0
    mkdir glibc-2.38-1
    tar -zxf ${glibc-wrap} -C glibc-2.38-1
    cp -av packagefiles/glibc-2.38/. glibc-2.38-1
    sed -i -e 's#set -e#set -ex#g' glibc-2.38-1/compile.sh
  )'';

  postPatch = ''
    patchShebangs --build $(find . -name '*.sh')
    patchShebangs --build $(find . -name '*.py')
    patchShebangs --build $(find . -name 'configure')
  '';

  mesonFlags = [
    "--buildtype=release"
    "-Ddirect=enabled"
    "-Dsgx=enabled"
    "-Dsgx_driver=upstream"
    "-Dwith_tools=enabled"
    "-Dwith_runtime=disabled"
  ];

  postFixup = ''
    set -e
    rm $out/lib/*.a
    rm -fr $out/lib/gramine
  '';

  format = "other";
  #enableParallelBuilding = false;

  nativeBuildInputs = with pkgs; [
    python
    meson
    nasm
    ninja
    cmake
    pkg-config
    nixsgx.sgx-sdk
    nixsgx.protobufc
    nixsgx.protobufc.dev
    nixsgx.libsgx-dcap-quote-verify.dev
    autoconf
    gawk
    bison
    patchelf
  ];

  buildInputs = [
    nixsgx.protobufc.dev
    nixsgx.protobufc.lib
  ];

  propagatedBuildInputs = [
    (python.withPackages my-python-packages)
  ];

  doCheck = false;

  meta = with lib; {
    description = "A lightweight usermode guest OS designed to run a single Linux application";
    homepage = "https://gramine.readthedocs.io/";
    platforms = [ "x86_64-linux" ];
    license = with licenses; [ lgpl3 ];
  };
}
