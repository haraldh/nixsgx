# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Matter Labs
{ lib, ... }:
final: prev:
# `sgxGramineContainer` relies on dockerTools and the SGX/Gramine packages,
# which are only available on x86_64-linux. Don't expose it elsewhere.
# The `or false` chain keeps this safe against snowfall's `fake-pkgs` probe,
# which has neither `stdenv` nor a populated `lib`.
lib.optionalAttrs
  ((prev.stdenv.hostPlatform.isx86_64 or false) && (prev.stdenv.hostPlatform.isLinux or false))
  {
    nixsgxLib.mkSGXContainer = final.lib.warn "`nixsgxLib.mkSGXContainer` is deprecated, use `pkgs.lib.tee.sgxGramineContainer`" final.lib.tee.sgxGramineContainer;

    lib = prev.lib.extend (
      libFinal: libPrev: {
        tee = libPrev.tee or { } // {
          sgxGramineContainer = args: final.callPackage ./sgxGramineContainer.nix args;
        };
      }
    );
  }
