{ nodejs_24, enableNpm ? false }:
nodejs_24.overrideAttrs (prevAttrs: {
  inherit enableNpm;
  configureFlags = prevAttrs.configureFlags ++ [ "--without-node-snapshot" ];
})
