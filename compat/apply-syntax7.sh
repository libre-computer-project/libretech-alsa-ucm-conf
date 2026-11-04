#!/bin/bash
# Hold the paths in compat/syntax7-paths.txt at a Syntax-7 upstream release so
# the tree loads on alsa-lib 1.2.14 (Debian 13), then check the result.
#
# Run from the repo top after a rebase onto a new upstream release; commit the
# result as the compat commit. Each listed path is replaced by its state at
# PIN_TAG (removed when PIN_TAG does not have it). Then compat/check-syntax.py
# must report no Syntax-8 construct and no include target the upstream base
# does not already miss.
#
# usage: compat/apply-syntax7.sh [PIN_TAG]      (default v1.2.14)

set -euo pipefail

pin=${1:-v1.2.14}
top=$(git rev-parse --show-toplevel)
cd "$top"
git rev-parse -q --verify "$pin^{commit}" >/dev/null || { echo "no such tag: $pin" >&2; exit 2; }
base=$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD)

while read -r path; do
	[[ -z $path || $path == \#* ]] && continue
	git rm -r -q --ignore-unmatch -- "$path"
	if git cat-file -e "$pin:$path" 2>/dev/null; then
		git checkout "$pin" -- "$path"
	fi
	echo "pinned $path @ $pin"
done < compat/syntax7-paths.txt

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
git archive "$base" ucm2 | tar -x -C "$scratch"
python3 compat/check-syntax.py --dangling-baseline "$scratch/ucm2" ucm2
