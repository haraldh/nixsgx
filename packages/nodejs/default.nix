{ lib
, callPackage
, nodejs_18
, libuv
, pkgs
, enableNpm ? false
}:

let
  libuv_patched = libuv.overrideAttrs (prevAttrs: {
    patches = (prevAttrs.patches or [ ]) ++ [ ./no-getifaddr.patch ];
  });
  callPackage' = p: args: callPackage p (args // { libuv = libuv_patched; });
  nodejs_libuv = nodejs_18.override { callPackage = callPackage'; };
  nodejs_patched = nodejs_libuv.overrideAttrs (prevAttrs: {
    inherit enableNpm;
  });
in
nodejs_patched
