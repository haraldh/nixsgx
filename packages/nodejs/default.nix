{ callPackage, lib, overrideCC, pkgs, buildPackages, fetchpatch, openssl, python3, nixsgx, enableNpm ? false }:

let
  # Clang 16+ cannot build Node v18 due to -Wenum-constexpr-conversion errors.
  # Use an older version of clang with the current libc++ for compatibility (e.g., with icu).
  ensureCompatibleCC = packages:
    if packages.stdenv.cc.isClang && lib.versionAtLeast (lib.getVersion packages.stdenv.cc.cc) "16"
      then overrideCC packages.llvmPackages_15.stdenv (packages.llvmPackages_15.stdenv.cc.override {
        inherit (packages.llvmPackages) libcxx;
        extraPackages = [ packages.llvmPackages.libcxxabi ];
      })
      else packages.stdenv;

  buildNodejs = callPackage ./nodejs.nix {
    inherit openssl;
    stdenv = ensureCompatibleCC pkgs;
    buildPackages = buildPackages // { stdenv = ensureCompatibleCC buildPackages; };
    python = python3;
    libuv = nixsgx.libuv;
  };
in
buildNodejs {
  inherit enableNpm;
  version = "18.18.2";
  sha256 = "sha256-ckni8K+UPsOFmVBPSyor0x+5OHhykbbMymyLrfAeO1Y=";
  patches = [
    ./disable-darwin-v8-system-instrumentation.patch
    ./bypass-darwin-xcrun-node16.patch
    ./revert-arm64-pointer-auth.patch
    ./node-npm-build-npm-package-logic.patch
    ./trap-handler-backport.patch
  ];
}
