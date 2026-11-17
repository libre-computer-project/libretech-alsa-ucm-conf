# alsa-ucm-conf-libre-computer: the overlay's files (src: build-overlay.sh's staged usr/share/alsa tree) under
# $out/share/alsa, and passthru.tree, nixpkgs' alsa-ucm-conf (ucm, ucm2) with them copied over it. A merged COPY,
# not a symlink join: our profiles link relatively into upstream's files (conf.d entries, the GXL profile's
# Amlogic/p241), and a link resolves only inside one tree.
{ lib, stdenvNoCC, runCommand, alsa-ucm-conf, src, version }:
let
  pkg = stdenvNoCC.mkDerivation {
    pname = "alsa-ucm-conf-libre-computer";
    inherit version src;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/alsa
      cp -a usr/share/alsa/. $out/share/alsa/
      runHook postInstall
    '';
    passthru.tree = runCommand "alsa-ucm-conf-with-libre-computer-${version}" { } ''
      mkdir -p $out/share/alsa
      for d in ucm ucm2; do
        cp -a ${alsa-ucm-conf}/share/alsa/$d $out/share/alsa/
        chmod -R u+w $out/share/alsa/$d
        if [ -d ${pkg}/share/alsa/$d ]; then cp -a ${pkg}/share/alsa/$d/. $out/share/alsa/$d/; fi
      done
      # every link our profiles add must land on a file of the merged tree
      bad=$(find -L $out/share/alsa -type l)
      if [ -n "$bad" ]; then echo "dangling links: $bad" >&2; exit 1; fi
    '';
    meta = {
      description = "ALSA Use Case Manager profiles for Libre Computer boards";
      homepage = "https://github.com/libre-computer-project/libretech-alsa-ucm-conf";
      license = lib.licenses.bsd3;
      platforms = lib.platforms.linux;
    };
  };
in
pkg
