#!/bin/bash
# build.sh -- build the alsa-ucm-conf-libre-computer .deb (and, for one release,
# the transitional libretech-alsa-ucm-conf .deb that moves hosts with the old
# name to it). Build only: nothing is installed or published.
#
# Builds exactly the committed HEAD: the tree is exported with `git archive`
# into a temporary directory, so uncommitted edits never reach the package and
# the checkout gets no debian/ build artifacts. The changelog entry is the HEAD
# commit; the version defaults to today's UTC date (YYYY.MM.DD).
#
# Output: out/<version>/ holding the .deb, .changes and .buildinfo. The LAST
# line on stdout is the path of the .changes file (build-install.sh reads it);
# everything else goes to stderr.
#
# Needs dpkg-buildpackage + debhelper. Run it on a build host, not the git host.
#
# Entry points: build.sh (build only) | build-install.sh (build, then install on
# a host for testing). Publishing is the release process's, through the signing
# chain to packages.libre.computer (claude infra/libre-computer/packages/
# publishing-isolation-plan.md); nothing here publishes.

set -euo pipefail

# --- Constants -------------------------------------------------------------
readonly SOURCE="libretech-alsa-ucm-conf"        # the source package keeps the project's name
readonly PACKAGE="alsa-ucm-conf-libre-computer"   # the binary package (package-naming policy rule 6.4)
readonly MAINTAINER="Da Xue <da@libre.computer>"
readonly DIST="linux"

# --- Helpers ---------------------------------------------------------------
log() { echo "build.sh: $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
	cat >&2 <<-EOF
	usage: $0 [--version VERSION] [--suite SUITE] [--commit SHA] [--out DIR]

	Build the $PACKAGE .deb from the committed HEAD (or, with no .git, the exported tree this script is
	in, whose commit --commit names) into out/<version>/ (or --out).
	  --version VERSION   the version (default: today's UTC date, YYYY.MM.DD; the release process passes the
	                      commit's date and commit, YYYYMMDD.HHMMSS.g<sha8>)
	  --suite SUITE       the release (trixie): its suffix, +deb13, goes on the version, as each release's
	                      build of this package differs and the apt pool is shared
	EOF
	exit 2
}

# --- Cleanup ---------------------------------------------------------------
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# --- Orchestration ---------------------------------------------------------
main() {
	local version="" suite="" commit="" out=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--version) [ $# -ge 2 ] || usage; version="$2"; shift 2 ;;
			--suite) [ $# -ge 2 ] || usage; suite="$2"; shift 2 ;;
			--commit) [ $# -ge 2 ] || usage; commit="$2"; shift 2 ;;
			--out) [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
			--help|-h) usage ;;
			*) usage ;;
		esac
	done

	local top self tree=0
	self=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
	if top=$(git -C "$self" rev-parse --show-toplevel 2>/dev/null); then :; else top=$self; tree=1; fi
	cd "$top"
	command -v dpkg-buildpackage >/dev/null || die "dpkg-buildpackage not found (install dpkg-dev + debhelper on this build host)"

	version=${version:-$(date -u +%Y.%m.%d)}
	case "$suite" in
		"") ;;
		trixie) version+=+deb13 ;;
		*) die "--suite: the whole tree is Debian 13's (trixie); the other releases take build-overlay.sh" ;;
	esac
	if [ "$tree" = 1 ]; then
		[ -n "$commit" ] || die "an exported tree needs --commit"
	else
		commit=$(git rev-parse HEAD)
		if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
			log "note: the checkout has uncommitted changes; they are NOT in the package (HEAD only)"
		fi
	fi
	out=${out:-$top/out/$version}
	[ -e "$out" ] && [ -n "$(ls -A "$out")" ] && die "$out holds a build: version $version was already built here (pass --version, or remove it)"

	TMP=$(mktemp -d)
	mkdir "$TMP/src"
	if [ "$tree" = 1 ]; then
		tar -C "$top" --exclude=./out -cf - . | tar -x -C "$TMP/src"
	else
		git archive HEAD | tar -x -C "$TMP/src"
	fi
	cat > "$TMP/src/debian/changelog" <<-EOF
	$SOURCE ($version) $DIST; urgency=medium

	  * $commit

	 -- $MAINTAINER  $(date -Ru)
	EOF

	log "building $PACKAGE $version from $commit"
	(cd "$TMP/src" && dpkg-buildpackage -uc --no-sign --build=all) >&2

	mkdir -p "$out"
	# the .changes/.buildinfo and the transitional .deb carry the source name
	mv "$TMP"/"${SOURCE}_${version}"_* "$TMP"/"${PACKAGE}_${version}"_* "$out/"
	log "built into $out:"
	ls -1 "$out" >&2
	echo "$out/${SOURCE}_${version}_all.changes"
}

main "$@"
