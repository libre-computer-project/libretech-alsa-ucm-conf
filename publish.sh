#!/bin/bash
# publish.sh -- publish one built libretech-alsa-ucm-conf package to the
# deb.libre.computer repository. Publish only: nothing is built.
#
# Uploads exactly ONE build: the given .changes file and the files it lists
# (checked against their sha256 sums in it), never whatever else sits in a
# directory. The repository then imports it (reprepro processincoming). A
# publish is public and cannot be taken back, so it asks first; --yes skips
# the question. A published build gets a PUBLISHED stamp in its out/ dir.
#
# Entry points: build.sh (build only) | publish.sh (publish only) |
# build-publish.sh (build, then publish) | build-install.sh (build, then
# install on a host for testing).

set -euo pipefail

# --- Constants -------------------------------------------------------------
readonly REPO_HOST="computer-libre-deb@deb.libre.computer"
readonly REPO_DIR="private/reprepro"

# --- Helpers ---------------------------------------------------------------
log() { echo "publish.sh: $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
	cat >&2 <<-EOF
	usage: $0 [--yes] [CHANGES]

	Publish one build to $REPO_HOST.
	  CHANGES   the build's .changes file (default: the newest out/*/*.changes)
	  --yes     do not ask before uploading
	EOF
	exit 2
}

# Files listed in the Checksums-Sha256 section of a .changes file: "sha size name".
changes_files() {
	awk '/^Checksums-Sha256:/{s=1; next} s && /^ /{print $1, $2, $3; next} s{exit}' "$1"
}

# --- Orchestration ---------------------------------------------------------
main() {
	local yes=0 changes=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--yes) yes=1; shift ;;
			--help|-h) usage ;;
			-*) usage ;;
			*) [ -z "$changes" ] || usage; changes="$1"; shift ;;
		esac
	done

	local top
	top=$(git -C "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" rev-parse --show-toplevel)
	if [ -z "$changes" ]; then
		changes=$(ls -1t "$top"/out/*/*.changes 2>/dev/null | head -n 1 || true)
		[ -n "$changes" ] || die "no build in $top/out/ (run build.sh first, or pass a .changes file)"
	fi
	[ -f "$changes" ] || die "not a file: $changes"
	local dir
	dir=$(cd "$(dirname "$changes")" && pwd)
	changes="$dir/$(basename "$changes")"
	[ -e "$dir/PUBLISHED" ] && die "$dir was already published ($(cat "$dir/PUBLISHED"))"

	local -a files=("$changes")
	local sha size name
	while read -r sha size name; do
		[ -f "$dir/$name" ] || die "$name (listed in $(basename "$changes")) is missing from $dir"
		[ "$(stat -c %s "$dir/$name")" = "$size" ] || die "$name: size differs from $(basename "$changes")"
		[ "$(sha256sum "$dir/$name" | cut -d' ' -f1)" = "$sha" ] || die "$name: sha256 differs from $(basename "$changes")"
		files+=("$dir/$name")
	done < <(changes_files "$changes")
	[ "${#files[@]}" -gt 1 ] || die "$(basename "$changes") lists no files"

	log "will upload to $REPO_HOST:$REPO_DIR/incoming and import:"
	printf '  %s\n' "${files[@]##*/}" >&2
	if [ "$yes" != 1 ]; then
		local reply
		read -r -n 1 -p "Publish? (y/n) " reply; echo >&2
		[ "${reply,,}" = y ] || die "not published"
	fi

	scp "${files[@]}" "$REPO_HOST:$REPO_DIR/incoming/"
	ssh "$REPO_HOST" "cd $REPO_DIR && reprepro processincoming incoming"
	date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/PUBLISHED"
	log "published $(basename "$changes")"
	log "repository disk use: $(ssh "$REPO_HOST" "df --output=pcent / | tail -n 1" | tr -d ' ')"
}

main "$@"
