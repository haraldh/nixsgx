{
  pkgs,
  nixsgx,
  ...
}:
# Depends on `sgx-psw`, which is only available on x86_64-linux.
(pkgs.writeShellScriptBin "restart-aesmd" ''
  ${pkgs.coreutils}/bin/mkdir -p /var/run/aesmd
  ${pkgs.killall}/bin/killall -q aesm_service
  exec ${nixsgx.sgx-psw}/bin/aesm_service --no-syslog
'').overrideAttrs
  (old: {
    meta = (old.meta or { }) // {
      platforms = [ "x86_64-linux" ];
    };
  })
