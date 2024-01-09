{ pkgs
, lib
, nixsgx
, ...
}:
pkgs.dockerTools.buildLayeredImage ({
  name = "gramine-dcap";
  tag = "latest";

  contents = pkgs.buildEnv ({
    name = "image-root";
    paths = with pkgs; [
      # strace
      bashInteractive
      # man
      # less
      # coreutils
      nixsgx.sgx-psw
      nixsgx.gramine
      nixsgx.libsgx-dcap-default-qpl
      nixsgx.restart-aesmd
    ];
    pathsToLink = [ "/bin" "/lib" "/etc" "/share/man" "/sbin" ];
    extraOutputsToInstall = [ "man" ];
    postBuild = ''
      	mkdir -p $out/var
      	ln -s /run $out/var/run
        # Remove wrapped binaries, they shouldn't be accessible via PATH.
        find $out/bin -maxdepth 1 -name ".*-wrapped" -type l -delete
    '';
  });
})
