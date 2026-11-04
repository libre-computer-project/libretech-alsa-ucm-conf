#!/bin/bash
# build-publish.sh -- build the libretech-alsa-ucm-conf .deb, then publish that
# build: build.sh, then publish.sh on the .changes file build.sh produced.
#
# Options go to the step that owns them: --version to build.sh, --yes to
# publish.sh.
#
# Entry points: build.sh (build only) | publish.sh (publish only) |
# build-publish.sh (build, then publish) | build-install.sh (build, then
# install on a host for testing).

set -euo pipefail

usage() {
	cat >&2 <<-EOF
	usage: $0 [--version VERSION] [--yes]

	Build the package (build.sh), then publish that build (publish.sh).
	  --version VERSION   package version (build.sh; default: today's UTC date)
	  --yes               do not ask before uploading (publish.sh)
	EOF
	exit 2
}

main() {
	local -a build_args=() publish_args=()
	while [ $# -gt 0 ]; do
		case "$1" in
			--version) [ $# -ge 2 ] || usage; build_args+=(--version "$2"); shift 2 ;;
			--yes) publish_args+=(--yes); shift ;;
			--help|-h) usage ;;
			*) usage ;;
		esac
	done

	local here changes
	here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
	changes=$("$here/build.sh" "${build_args[@]}" | tail -n 1)
	"$here/publish.sh" "${publish_args[@]}" "$changes"
}

main "$@"
