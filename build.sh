#!/bin/bash
# build.sh -- build the libretech-alsa-ucm-conf .deb. Build only: nothing is
# installed or published.
#
# Builds exactly the committed HEAD: the tree is exported with `git archive`
# into a temporary directory, so uncommitted edits never reach the package and
# the checkout gets no debian/ build artifacts. The changelog entry is the HEAD
# commit; the version defaults to today's UTC date (YYYY.MM.DD).
#
# Output: out/<version>/ holding the .deb, .changes and .buildinfo. The LAST
# line on stdout is the path of the .changes file (publish.sh and the other
# entry points read it); everything else goes to stderr.
#
# Needs dpkg-buildpackage + debhelper. Run it on a build host, not the git host.
#
# Entry points: build.sh (build only) | publish.sh (publish only) |
# build-publish.sh (build, then publish) | build-install.sh (build, then
# install on a host for testing).

set -euo pipefail

# --- Constants -------------------------------------------------------------
readonly PACKAGE="libretech-alsa-ucm-conf"
readonly MAINTAINER="Da Xue <da@libre.computer>"
readonly DIST="linux"

# --- Helpers ---------------------------------------------------------------
log() { echo "build.sh: $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
	cat >&2 <<-EOF
	usage: $0 [--version VERSION]

	Build the $PACKAGE .deb from the committed HEAD into out/<version>/.
	  --version VERSION   package version (default: today's UTC date, YYYY.MM.DD)
	EOF
	exit 2
}

# --- Cleanup ---------------------------------------------------------------
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# --- Orchestration ---------------------------------------------------------
main() {
	local version=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--version) [ $# -ge 2 ] || usage; version="$2"; shift 2 ;;
			--help|-h) usage ;;
			*) usage ;;
		esac
	done

	local top
	top=$(git -C "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" rev-parse --show-toplevel)
	cd "$top"
	command -v dpkg-buildpackage >/dev/null || die "dpkg-buildpackage not found (install dpkg-dev + debhelper on this build host)"

	version=${version:-$(date -u +%Y.%m.%d)}
	local commit out
	commit=$(git rev-parse HEAD)
	out="$top/out/$version"
	[ -e "$out" ] && die "$out exists: version $version was already built here (pass --version, or remove it)"
	if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
		log "note: the checkout has uncommitted changes; they are NOT in the package (HEAD only)"
	fi

	TMP=$(mktemp -d)
	mkdir "$TMP/src"
	git archive HEAD | tar -x -C "$TMP/src"
	cat > "$TMP/src/debian/changelog" <<-EOF
	$PACKAGE ($version) $DIST; urgency=medium

	  * $commit

	 -- $MAINTAINER  $(date -Ru)
	EOF

	log "building $PACKAGE $version from $commit"
	(cd "$TMP/src" && dpkg-buildpackage -uc --no-sign --build=all) >&2

	mkdir -p "$out"
	mv "$TMP"/"${PACKAGE}_${version}"_* "$out/"
	log "built into $out:"
	ls -1 "$out" >&2
	echo "$out/${PACKAGE}_${version}_all.changes"
}

main "$@"
