{ lib
, callPackage
, nodejs_18
, nixsgx
, enableNpm ? false
}:

let
  callPackage' = p: args: callPackage p (args // { libuv = nixsgx.libuv; });
  nodejs_libuv = nodejs_18.override { callPackage = callPackage'; };
  nodejs_patched = nodejs_libuv.overrideAttrs (prevAttrs: {
    inherit enableNpm;
  });
in
nodejs_patched
