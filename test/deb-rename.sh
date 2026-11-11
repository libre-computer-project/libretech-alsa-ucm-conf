#!/bin/bash
# deb-rename.sh -- the .deb rename libretech-alsa-ucm-conf -> alsa-ucm-conf-libre-computer (package-naming policy
# rule 6.5), in copies of a Debian 13 image that has the old package installed (an os-factory image does). Both ways
# a board takes the new name:
#   T  transitional: the new package with the transitional libretech-alsa-ucm-conf, as `apt upgrade` does while the
#      transitional package is in the repository
#   B  Breaks: the new package alone, as libre-computer-archive-keyring's migration does once it is not; apt
#      removes the old name
# Each must leave the UCM tree in /usr/share/alsa/ucm2 owned by the new name, alsa-ucm-conf still provided (nothing
# that depends on it broken: apt-get check clean) and dpkg's database consistent.
#
#   sudo test/deb-rename.sh <image.img> <dir with the two built .debs>

set -uo pipefail
usage="usage: sudo test/deb-rename.sh <image.img> <debs-dir>"
img=${1:?$usage}
debs=$(realpath -e "${2:?$usage}")
[[ $EUID -eq 0 ]] || { echo "needs root" >&2; exit 1; }
readonly NEW=alsa-ucm-conf-libre-computer OLD=libretech-alsa-ucm-conf
# one upstream file and one Libre Computer profile file of the whole tree
readonly FILES=(/usr/share/alsa/ucm2/ucm.conf /usr/share/alsa/ucm2/Amlogic/gxl/gxl.conf)
# the image copies go beside the image (a disk the caller chose), never /tmp (tmpfs)
W=$(mktemp -d "$(dirname "$(realpath -e "$img")")/deb-rename.XXXXXX")
PASS=0 FAIL=0
check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); echo "PASS  $what"; else FAIL=$((FAIL + 1)); echo "FAIL  $what"; fi; }
mnt="" loop=""
cleanup() {
	[[ -z "$mnt" ]] || { umount -R "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; }
	[[ -z "$loop" ]] || losetup -d "$loop" 2>/dev/null || true
	mnt="" loop=""
	rm -f "$W/t.img"
}
trap 'cleanup; rm -rf "$W"' EXIT
deb() { find "$debs" -maxdepth 1 -name "$1_*_all.deb" -print -quit; }
for p in $NEW $OLD; do
	[[ -n "$(deb "$p")" ]] || { echo "no $p .deb in $debs" >&2; exit 1; }
done
# a package that Depends on the old name keeps it satisfied once the transitional package is gone (rule 6.5)
check "P: $NEW Provides $OLD at its own version" bash -c "[[ \$(dpkg-deb -f '$(deb $NEW)' Provides) == *'$OLD (= '\$(dpkg-deb -f '$(deb $NEW)' Version)')'* ]]"
setup() {
	cp --reflink=auto "$img" "$W/t.img"
	loop=$(losetup -fP --show "$W/t.img")
	udevadm settle
	mnt=$(mktemp -d)
	mount "${loop}p2" "$mnt"
	local m
	for m in dev dev/pts proc sys; do mount --bind "/$m" "$mnt/$m"; done
	mount -t tmpfs tmpfs "$mnt/run"
	mount -t tmpfs tmpfs "$mnt/tmp"
	cp "$(deb $NEW)" "$(deb $OLD)" "$mnt/tmp/"
}
installed() { [[ "$(chroot "$mnt" dpkg-query -W -f '${db:Status-Status}' "$1" 2>/dev/null)" == installed ]]; }
apt_local() { # local .debs through apt, which orders the swap as a board's upgrade does (plain dpkg -i cannot)
	local a=() p
	for p in "$@"; do a+=("/tmp/$(basename "$(deb "$p")")"); done
	chroot "$mnt" env DEBIAN_FRONTEND=noninteractive apt-get -y -q install "${a[@]}" > "$W/apt.log" 2>&1 ||
		{ echo "-- apt failed:"; tail -n 12 "$W/apt.log"; }
}
works() { # the tree, its owner, alsa-ucm-conf still satisfied, and the database
	local tag=$1 f
	for f in "${FILES[@]}"; do
		check "$tag: $f present and owned by $NEW alone" bash -c "test -s '$mnt$f' && [[ \$(chroot '$mnt' dpkg -S '$f') == '$NEW: $f' ]]"
	done
	check "$tag: Debian's alsa-ucm-conf not installed (its role provided by $NEW)" bash -c "$(declare -f installed); mnt='$mnt'; ! installed alsa-ucm-conf"
	check "$tag: no broken dependency (apt-get check clean)" chroot "$mnt" apt-get -q check
	check "$tag: dpkg's database is consistent (dpkg --audit says nothing)" bash -c "[[ -z \$(chroot '$mnt' dpkg --audit) ]]"
}

echo "== T: the transitional package with the new one"
setup
check "T: the image has the old name installed (precondition)" bash -c "$(declare -f installed); mnt='$mnt'; installed $OLD"
apt_local $NEW $OLD
check "T: the new name installed, the old one now transitional" bash -c "$(declare -f installed); mnt='$mnt'; installed $NEW && [[ \$(chroot '$mnt' dpkg-query -W -f '\${Section}' $OLD) == oldlibs ]]"
works T
chroot "$mnt" env DEBIAN_FRONTEND=noninteractive apt-get -y -q remove $OLD > "$W/rm.log" 2>&1
check "T: the transitional package removed, the new one kept" bash -c "$(declare -f installed); mnt='$mnt'; ! installed $OLD && installed $NEW"
works T-after-removal
cleanup

echo "== B: the new package alone (the old name gone from the repository)"
setup
apt_local $NEW
check "B: the new name installed, the old one removed by Breaks" bash -c "$(declare -f installed); mnt='$mnt'; installed $NEW && ! installed $OLD"
works B
cleanup

echo "deb-rename: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
