# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
{
  pkgs,
  stdenv,
  hello,
  isAzure ? false,
  container-name ? "nixsgx-test-sgx-dcap",
  tag ? "latest",
}:
# `sgxGramineContainer` (and the SGX/Gramine toolchain it relies on) is only
# available on x86_64-linux. Expose a platform-restricted stub elsewhere so the
# package still evaluates but is skipped by builds.
if stdenv.hostPlatform.isx86_64 && stdenv.hostPlatform.isLinux then
  pkgs.lib.tee.sgxGramineContainer {
    name = container-name;
    inherit tag isAzure;

    packages = [ hello ];
    entrypoint = pkgs.lib.meta.getExe hello;

    extraCmd = "echo \"Starting ${container-name}\"; gramine-sgx-sigstruct-view app.sig";

    manifest = {
      sgx = {
        edmm_enable = false;
        enclave_size = "32M";
        max_threads = 4;
      };
    };
  }
else
  pkgs.runCommand container-name { meta.platforms = [ "x86_64-linux" ]; } "exit 1"
