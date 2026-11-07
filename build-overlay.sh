#!/bin/bash
# build-overlay.sh -- build the libretech-alsa-ucm-conf OVERLAY: only the Libre Computer profiles, installed beside
# the distribution's own alsa-ucm-conf (Debian/Ubuntu), alsa-ucm (Fedora) or alsa-ucm-conf (Arch), for every
# distribution whose alsa-lib is not the one the whole tree targets. build.sh builds the whole tree (it replaces
# alsa-ucm-conf; alsa-lib 1.2.14, Debian 13). Build only: nothing is installed or published.
#
#   build-overlay.sh --format deb|rpm|arch [--flavour overlay|overlay-legacy] [--version YYYY.MM.DD] [--out DIR]
#
#   overlay         every file HEAD adds over its upstream base (the merge-base with upstream/master) under init/,
#                   ucm/ and ucm2/: our profiles, nothing upstream ships. For alsa-ucm-conf >= 1.2.11 (Ubuntu 26.04,
#                   Fedora, Arch)
#   overlay-legacy  the same, plus the upstream files our profiles resolve to that alsa-ucm-conf < 1.2.11 lacks
#                   (packaging/overlay-legacy.list: Amlogic/p241, which the GXL profile links to). For Debian 12
#                   (1.2.8) and Ubuntu 24.04 (1.2.10)
#
# Versions: <date>+overlay / <date>+overlay.legacy, so the apt pool (shared by every suite) never holds two files of
# one name. The package refuses to be built if a staged file is not a regular file or a link inside the tree.
# Builds exactly the committed HEAD (git archive); run it in this checkout on a build host. The LAST line on stdout
# is the package's path. infra/libre-computer/packages/multi-distro-packages-plan.md U2.

set -euo pipefail
IFS=$'\n\t'

readonly PACKAGE=libretech-alsa-ucm-conf
readonly MAINTAINER="Da Xue <da@libre.computer>"
readonly BUILD_HOST=deb.libre.computer   # what a package header names, never the machine that built it
readonly PACKAGER="autobuild <autobuild@deb.libre.computer>"
readonly PREFIX=usr/share/alsa

log() { printf 'build-overlay: %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

T=""
cleanup() { [[ -n $T && -d $T ]] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# the overlay's paths, repo-relative: what HEAD adds over the upstream base, plus the legacy list for that flavour
overlay_paths() {
  local flavour=$1 base
  base=$(git merge-base HEAD upstream/master) || die "no merge-base with upstream/master (fetch the upstream remote)"
  git diff --name-only --no-renames --diff-filter=A "$base" HEAD -- init ucm ucm2
  if [[ $flavour == overlay-legacy ]]; then
    grep -v -e '^#' -e '^$' packaging/overlay-legacy.list
  fi
}

deb_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 commit
  commit=$(git rev-parse --short=12 HEAD)
  mkdir -p "$root/DEBIAN"
  cat >"$root/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $version
Architecture: all
Multi-Arch: foreign
Maintainer: $MAINTAINER
Depends: alsa-ucm-conf
Section: libs
Priority: optional
Description: ALSA Use Case Manager profiles for Libre Computer boards
 The Libre Computer board profiles (Amlogic, MediaTek) alone, installed beside
 the distribution's alsa-ucm-conf; no file of it is replaced. Built from
 commit $commit.
EOF
  mkdir -p "$out"
  dpkg-deb --root-owner-group -Zxz --build "$root" "$out/${PACKAGE}_${version}_all.deb" >&2
  echo "$out/${PACKAGE}_${version}_all.deb"
}

rpm_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 ver rel
  ver=${version%%+*}; rel=1.${version#*+}; rel=${rel//+/.}
  mkdir -p "$T/rpm/SPECS"
  {
    cat <<EOF
%global debug_package %{nil}
%global __os_install_post %{nil}
Name: $PACKAGE
Version: $ver
Release: $rel
Summary: ALSA Use Case Manager profiles for Libre Computer boards
License: BSD-3-Clause
URL: https://github.com/libre-computer-project/libretech-alsa-ucm-conf
BuildArch: noarch
AutoReqProv: no
Requires: alsa-ucm

%description
The Libre Computer board profiles (Amlogic, MediaTek) alone, installed beside the distribution's alsa-ucm; no file
of it is replaced.

%install
cp -a $root/. %{buildroot}/

%files
EOF
    (cd "$root" && find . \( -type f -o -type l \) -printf '/%P\n' | sort)
  } >"$T/rpm/SPECS/$PACKAGE.spec"
  rpmbuild --quiet --define "_topdir $T/rpm" --define "_buildhost $BUILD_HOST" -bb "$T/rpm/SPECS/$PACKAGE.spec" >&2
  mkdir -p "$out"
  cp "$T/rpm/RPMS/noarch/$PACKAGE-$ver-$rel.noarch.rpm" "$out/"
  echo "$out/$PACKAGE-$ver-$rel.noarch.rpm"
}

arch_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 ver
  ver=${version//+/.}   # pacman: no '+' wanted in a pkgver; 2026.11.07.overlay.legacy
  mkdir -p "$T/arch"
  cp -a "$root" "$T/arch/root"
  cat >"$T/arch/PKGBUILD" <<EOF
pkgname=$PACKAGE
pkgver=$ver
pkgrel=1
pkgdesc='ALSA Use Case Manager profiles for Libre Computer boards'
arch=(any)
url='https://github.com/libre-computer-project/libretech-alsa-ucm-conf'
license=(BSD-3-Clause)
depends=(alsa-ucm-conf)
options=(!strip !debug !emptydirs)
package() { cp -a "\$startdir/root/." "\$pkgdir/"; }
EOF
  (cd "$T/arch" && BUILDDIR=$T/arch/b PKGDEST=$T/arch SRCDEST=$T/arch PKGEXT=.pkg.tar.zst PACKAGER=$PACKAGER \
    makepkg --nodeps --noconfirm --force >&2)
  mkdir -p "$out"
  cp "$T/arch/$PACKAGE-$ver-1-any.pkg.tar.zst" "$out/"
  echo "$out/$PACKAGE-$ver-1-any.pkg.tar.zst"
}

main() {
  local format="" flavour=overlay version="" out=""
  while (($#)); do
    case $1 in
      --format) format=${2:?}; shift 2 ;;
      --flavour) flavour=${2:?}; shift 2 ;;
      --version) version=${2:?}; shift 2 ;;
      --out) out=${2:?}; shift 2 ;;
      *) die "usage: build-overlay.sh --format deb|rpm|arch [--flavour overlay|overlay-legacy] [--version YYYY.MM.DD] [--out DIR]" ;;
    esac
  done
  case $format in deb | rpm | arch) ;; *) die "--format deb, rpm or arch" ;; esac
  case $flavour in overlay) ;; overlay-legacy) ;; *) die "--flavour overlay or overlay-legacy" ;; esac
  version=${version:-$(date -u +%Y.%m.%d)}
  [[ $version =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]] || die "--version $version is not YYYY.MM.DD"
  version+="+${flavour/-/.}"
  cd "$(git -C "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" rev-parse --show-toplevel)"
  out=${out:-$PWD/out/$version}
  [[ -z $(git status --porcelain --untracked-files=no) ]] || log "note: uncommitted changes are NOT in the package (HEAD only)"

  T=$(mktemp -d /var/tmp/ucm-overlay.XXXXXX)
  local paths n
  mapfile -t paths < <(overlay_paths "$flavour")
  n=${#paths[@]}
  ((n > 0)) || die "the overlay is empty"
  mkdir -p "$T/root/$PREFIX"
  git archive HEAD -- "${paths[@]}" | tar -x -C "$T/root/$PREFIX"
  # every staged path is a regular file or a link that resolves inside the staged tree or to a path the
  # distribution's own package ships (a link is checked by the install review, not here)
  local bad
  bad=$(cd "$T/root" && find . ! -type f ! -type l ! -type d | head -1)
  [[ -z $bad ]] || die "staged $bad is not a file or a link"
  find "$T/root" -type f -exec chmod 0644 {} +
  find "$T/root" -type d -exec chmod 0755 {} +
  log "$PACKAGE $version ($flavour, $n files) from $(git rev-parse --short=12 HEAD)"
  "${format}_package" "$T/root" "$version" "$out"
}

main "$@"
