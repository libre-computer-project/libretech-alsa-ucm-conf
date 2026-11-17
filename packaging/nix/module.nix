# hardware.alsa.libreComputerUcm: ALSA reads nixpkgs' alsa-ucm-conf with our profiles added. nixpkgs' alsa-lib links
# its share/alsa/{ucm,ucm2} to alsa-ucm-conf, and replacing that package would rebuild alsa-lib and everything above
# it; alsa-lib reads ALSA_CONFIG_UCM2 / ALSA_CONFIG_UCM instead when they are set, so the module sets them for login
# sessions and for the audio daemons (PipeWire, WirePlumber, PulseAudio), which do not inherit a session's.
# alsactl's init files (share/alsa/init) are not covered: alsactl reads them from its own data directory.
self:
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.alsa.libreComputerUcm;
  tree = (pkgs.callPackage ./package.nix { src = ./root; version = import ./version.nix; }).tree;
  env = {
    ALSA_CONFIG_UCM2 = "${tree}/share/alsa/ucm2";
    ALSA_CONFIG_UCM = "${tree}/share/alsa/ucm";
  };
  pw = config.services.pipewire;
in
{
  options.hardware.alsa.libreComputerUcm.enable =
    lib.mkEnableOption "the Libre Computer board audio profiles (ALSA UCM)";

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { environment.sessionVariables = env; }
    (lib.mkIf (pw.enable && !pw.systemWide) {
      systemd.user.services.pipewire.environment = env;
      systemd.user.services.wireplumber.environment = env;
    })
    (lib.mkIf (pw.enable && pw.systemWide) {
      systemd.services.pipewire.environment = env;
      systemd.services.wireplumber.environment = env;
    })
    (lib.mkIf config.services.pulseaudio.enable {
      systemd.user.services.pulseaudio.environment = env;
    })
  ]);
}
