#!/bin/bash
# build-install.sh -- build the libretech-alsa-ucm-conf .deb, then install that
# build on one host for testing before it is published.
#
# Copies the .deb to the host and installs it with apt, which resolves its
# dependencies (libasound2t64) and replaces Debian's alsa-ucm-conf. A dry run
# is printed first and the install refuses if apt would remove any package
# other than alsa-ucm-conf.
#
# Entry points: build.sh (build only) | publish.sh (publish only) |
# build-publish.sh (build, then publish) | build-install.sh (build, then
# install on a host for testing).

set -euo pipefail

readonly PACKAGE="libretech-alsa-ucm-conf"

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

	local here changes deb remote
	here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
	changes=$("$here/build.sh" "${build_args[@]}" | tail -n 1)
	deb="${changes%.changes}.deb"
	[ -f "$deb" ] || die "build produced no $deb"
	remote="/tmp/$(basename "$deb")"

	scp "$deb" "$target:$remote"
	log "dry run on $target:"
	local plan
	plan=$(ssh "$target" "sudo apt-get install --dry-run $remote")
	grep -E '^(Remv|Inst)' <<<"$plan" >&2 || true
	if grep -E '^Remv' <<<"$plan" | grep -vqE '^Remv alsa-ucm-conf '; then
		die "apt would remove more than alsa-ucm-conf on $target; not installing"
	fi
	ssh "$target" "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $remote && rm -f $remote"
	log "installed $(basename "$deb") on $target"
}

main "$@"
