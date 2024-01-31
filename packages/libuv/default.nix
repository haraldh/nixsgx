{ lib
, libuv
}:
libuv.overrideAttrs (prevAttrs: {
    patches = (prevAttrs.patches or [ ]) ++ [
      ./no-getifaddr.patch
      ./no-eventfd.patch
    ];
  })
