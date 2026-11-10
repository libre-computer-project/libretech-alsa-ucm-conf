#!/bin/bash
# build-install.sh -- build the alsa-ucm-conf-libre-computer .deb, then install
# that build on one host for testing before it is published.
#
# Copies the .deb and the transitional libretech-alsa-ucm-conf .deb to the host
# and installs both with apt, which resolves their dependencies (libasound2t64),
# replaces Debian's alsa-ucm-conf and moves a host with the old name to the new
# one, as an upgrade from the repository does. A dry run is printed first and
# the install refuses if apt would remove any package other than alsa-ucm-conf
# or libretech-alsa-ucm-conf.
#
# Entry points: build.sh (build only) | publish.sh (publish only) |
# build-publish.sh (build, then publish) | build-install.sh (build, then
# install on a host for testing).

set -euo pipefail

readonly PACKAGE="alsa-ucm-conf-libre-computer"
readonly OLD_PACKAGE="libretech-alsa-ucm-conf"   # transitional, for one release (package-naming policy rule 6.5)

log() { echo "build-install.sh: $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
	cat >&2 <<-EOF
	usage: $0 [--version VERSION] USER@HOST

	Build the package (build.sh), then install that build on USER@HOST with apt.
	  --version VERSION   package version (build.sh; default: today's UTC date)
	EOF
	exit 2
}

main() {
	local -a build_args=()
	local target=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--version) [ $# -ge 2 ] || usage; build_args+=(--version "$2"); shift 2 ;;
			--help|-h) usage ;;
			-*) usage ;;
			*) [ -z "$target" ] || usage; target="$1"; shift ;;
		esac
	done
	[ -n "$target" ] || usage

	local here changes dir version deb old remote remote_old
	here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
	changes=$("$here/build.sh" "${build_args[@]}" | tail -n 1)
	dir=$(dirname "$changes")
	version=$(basename "$dir")
	deb="$dir/${PACKAGE}_${version}_all.deb"
	old="$dir/${OLD_PACKAGE}_${version}_all.deb"
	[ -f "$deb" ] || die "build produced no $deb"
	[ -f "$old" ] || die "build produced no $old"
	remote="/tmp/$(basename "$deb")"
	remote_old="/tmp/$(basename "$old")"

	scp "$deb" "$old" "$target:/tmp/"
	log "dry run on $target:"
	local plan
	plan=$(ssh "$target" "sudo apt-get install --dry-run $remote $remote_old")
	grep -E '^(Remv|Inst)' <<<"$plan" >&2 || true
	if grep -E '^Remv' <<<"$plan" | grep -vqE "^Remv (alsa-ucm-conf|$OLD_PACKAGE) "; then
		die "apt would remove more than alsa-ucm-conf on $target; not installing"
	fi
	ssh "$target" "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $remote $remote_old && rm -f $remote $remote_old"
	log "installed $(basename "$deb") and $(basename "$old") on $target"
}

main "$@"
