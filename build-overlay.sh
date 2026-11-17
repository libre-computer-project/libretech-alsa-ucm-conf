#!/bin/bash
# build-overlay.sh -- build the Libre Computer UCM OVERLAY: only the Libre Computer profiles, installed beside
# the distribution's own alsa-ucm-conf (Debian/Ubuntu), alsa-ucm (Fedora) or alsa-ucm-conf (Arch), for every
# distribution whose alsa-lib is not the one the whole tree targets. build.sh builds the whole tree (it replaces
# alsa-ucm-conf; alsa-lib 1.2.14, Debian 13). Build only: nothing is installed or published.
#
#   build-overlay.sh --format deb|rpm|arch|nix [--flavour overlay|overlay-legacy] [--version YYYY.MM.DD]
#                    [--dist .tw|.lp<NNN>] [--release N] [--out DIR]
#
#   --format nix    no package: the flake packages.libre.computer publishes, DIR/flake (packaging/nix/ plus the
#                   staged files as root.tar, its links kept, and version.nix) and DIR/alsa-ucm-conf-libre-computer.tar.gz (that flake
#                   under one top directory, Nix's tarball flakes); the builders build DIR/flake for the cache.
#                   NixOS's alsa-ucm-conf is >= 1.2.11: --flavour overlay
#   The rpm requires (alsa-ucm or alsa-ucm-conf): Fedora's name, then openSUSE's, so the same files install on
#   both. --release N (rpm only) [1]: a packaging fix on the same version gets a new release (2.overlay), so a
#   published file name never changes.
#   --dist .tw|.lp<NNN> (rpm only) tags the release for one openSUSE release (1.overlay.tw): the publisher
#   places an openSUSE package by that tag, and an untagged build goes to Fedora.
#
#   overlay         every file HEAD adds over its upstream base (the merge-base with upstream/master) under init/,
#                   ucm/ and ucm2/, except what the compat pins restore (compat/syntax7-paths.txt: upstream
#                   v1.2.14 files): our profiles, nothing upstream ships. For alsa-ucm-conf >= 1.2.11 (Ubuntu 26.04,
#                   Fedora, Arch)
#   overlay-legacy  the same, plus the upstream files our profiles resolve to that alsa-ucm-conf < 1.2.11 lacks
#                   (packaging/overlay-legacy.list: Amlogic/p241, which the GXL profile links to). For Debian 12
#                   (1.2.8) and Ubuntu 24.04 (1.2.10)
#
# Versions: <date>+overlay / <date>+overlay.legacy, so the apt pool (shared by every suite) never holds two files of
# one name. The package refuses to be built if a staged file is not a regular file or a link inside the tree.
# Builds exactly the committed HEAD (git archive); run it in this checkout on a build host. The LAST line on stdout
# is the package's path. infra/libre-computer/packages/multi-distro-packages-plan.md U2.
#
# Names (package-naming policy rule 6.4): alsa-ucm-conf-libre-computer (deb, Arch), alsa-ucm-libre-computer (Fedora),
# renamed from libretech-alsa-ucm-conf (rule 6.5): the deb Breaks/Replaces the old name below this version, Provides it, and --format
# deb also builds the transitional libretech-alsa-ucm-conf .deb (its path printed on the line before the package's);
# the rpm Obsoletes + Provides it; the pacman package replaces / conflicts / provides it.

set -euo pipefail
IFS=$'\n\t'

readonly OLD_PACKAGE=libretech-alsa-ucm-conf      # the name before 2026-11-10, every format
readonly DEB_PACKAGE=alsa-ucm-conf-libre-computer
readonly RPM_PACKAGE=alsa-ucm-libre-computer
readonly ARCH_PACKAGE=alsa-ucm-conf-libre-computer
readonly NIX_PACKAGE=alsa-ucm-conf-libre-computer
readonly MAINTAINER="Da Xue <da@libre.computer>"
readonly BUILD_HOST=deb.libre.computer   # what a package header names, never the machine that built it
readonly ARCH_PACKAGER="autobuild <autobuild@deb.libre.computer>"   # makepkg's PACKAGER
readonly PREFIX=usr/share/alsa

log() { printf 'build-overlay: %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

T=""
DIST=""   # --dist: the openSUSE dist tag of an rpm build
RELEASE=1 # --release: the rpm release number, raised for a packaging fix on the same version
cleanup() { [[ -n $T && -d $T ]] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# the overlay's paths, repo-relative: what HEAD adds over the upstream base, plus the legacy list for that flavour
overlay_paths() {
  local flavour=$1 base
  base=$(git merge-base HEAD upstream/master) || die "no merge-base with upstream/master (fetch the upstream remote)"
  # the compat pins (compat/syntax7-paths.txt) re-add upstream v1.2.14 files for the whole tree: upstream's, not
  # ours, and a distro package's own copy would clash with them
  local pins
  pins=$(git show HEAD:compat/syntax7-paths.txt | grep -v -e '^#' -e '^$')
  git diff --name-only --no-renames --diff-filter=A "$base" HEAD -- init ucm ucm2 |
    PINS=$pins awk 'BEGIN { n = split(ENVIRON["PINS"], p, "\n") }
      { for (i = 1; i <= n; i++) if ($0 == p[i] || index($0, p[i] "/") == 1) next; print }'
  if [[ $flavour == overlay-legacy ]]; then
    grep -v -e '^#' -e '^$' packaging/overlay-legacy.list
  fi
}

deb_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 commit
  commit=$(git rev-parse --short=12 HEAD)
  mkdir -p "$root/DEBIAN"
  cat >"$root/DEBIAN/control" <<EOF
Package: $DEB_PACKAGE
Version: $version
Architecture: all
Multi-Arch: foreign
Maintainer: $MAINTAINER
Depends: alsa-ucm-conf
Breaks: $OLD_PACKAGE (<< $version)
Replaces: $OLD_PACKAGE (<< $version)
Provides: $OLD_PACKAGE (= $version)
Section: libs
Priority: optional
Description: ALSA Use Case Manager profiles for Libre Computer boards
 The Libre Computer board profiles (Amlogic, MediaTek) alone, installed beside
 the distribution's alsa-ucm-conf; no file of it is replaced. Built from
 commit $commit.
EOF
  # the transitional package under the old name, for one release: it pulls in the new one and is otherwise empty
  local troot=$T/transitional
  mkdir -p "$troot/DEBIAN"
  cat >"$troot/DEBIAN/control" <<EOF
Package: $OLD_PACKAGE
Version: $version
Architecture: all
Maintainer: $MAINTAINER
Depends: $DEB_PACKAGE (= $version)
Section: oldlibs
Priority: optional
Description: transitional package for $DEB_PACKAGE
 The Libre Computer board profiles are now $DEB_PACKAGE. This package
 pulls it in and can be removed.
EOF
  mkdir -p "$out"
  dpkg-deb --root-owner-group -Zxz --build "$troot" "$out/${OLD_PACKAGE}_${version}_all.deb" >&2
  dpkg-deb --root-owner-group -Zxz --build "$root" "$out/${DEB_PACKAGE}_${version}_all.deb" >&2
  echo "$out/${OLD_PACKAGE}_${version}_all.deb"
  echo "$out/${DEB_PACKAGE}_${version}_all.deb"
}

rpm_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 ver rel
  ver=${version%%+*}; rel=$RELEASE.${version#*+}; rel=${rel//+/.}$DIST
  mkdir -p "$T/rpm/SPECS"
  {
    cat <<EOF
%global debug_package %{nil}
%global __os_install_post %{nil}
Name: $RPM_PACKAGE
Version: $ver
Release: $rel
Summary: ALSA Use Case Manager profiles for Libre Computer boards
License: BSD-3-Clause
URL: https://github.com/libre-computer-project/libretech-alsa-ucm-conf
BuildArch: noarch
AutoReqProv: no
Requires: (alsa-ucm or alsa-ucm-conf)
# renamed from $OLD_PACKAGE (package-naming policy rule 6.5): an upgrade replaces the old name
Obsoletes: $OLD_PACKAGE < %{version}-%{release}
Provides: $OLD_PACKAGE = %{version}-%{release}

%description
The Libre Computer board profiles (Amlogic, MediaTek) alone, installed beside the distribution's alsa-ucm; no file
of it is replaced.

%install
cp -a $root/. %{buildroot}/

%files
EOF
    # the directories it adds below share/alsa/{ucm,ucm2,init}, so an erase removes them; those three (and
    # share/alsa) are the distribution's alsa-ucm / alsa-lib's
    # every path quoted: upstream names carry spaces (conf.d/tegra/...), and one of ours could too
    (cd "$root" && find . -mindepth 5 -type d -printf '%%dir "/%P"\n' | sort)
    (cd "$root" && find . \( -type f -o -type l \) -printf '"/%P"\n' | sort)
  } >"$T/rpm/SPECS/$RPM_PACKAGE.spec"
  rpmbuild --quiet --define "_topdir $T/rpm" --define "_buildhost $BUILD_HOST" -bb "$T/rpm/SPECS/$RPM_PACKAGE.spec" >&2
  mkdir -p "$out"
  cp "$T/rpm/RPMS/noarch/$RPM_PACKAGE-$ver-$rel.noarch.rpm" "$out/"
  echo "$out/$RPM_PACKAGE-$ver-$rel.noarch.rpm"
}

arch_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 ver
  ver=${version//+/.}   # pacman: no '+' wanted in a pkgver; 2026.11.07.overlay.legacy
  mkdir -p "$T/arch"
  cp -a "$root" "$T/arch/root"
  cat >"$T/arch/PKGBUILD" <<EOF
pkgname=$ARCH_PACKAGE
pkgver=$ver
pkgrel=1
pkgdesc='ALSA Use Case Manager profiles for Libre Computer boards'
arch=(any)
url='https://github.com/libre-computer-project/libretech-alsa-ucm-conf'
license=(BSD-3-Clause)
depends=(alsa-ucm-conf)
# renamed from $OLD_PACKAGE (package-naming policy rule 6.5)
provides=("$OLD_PACKAGE=\$pkgver-\$pkgrel")
conflicts=($OLD_PACKAGE)
replaces=($OLD_PACKAGE)
options=(!strip !debug !emptydirs)
package() { cp -a "\$startdir/root/." "\$pkgdir/"; }
EOF
  (cd "$T/arch" && BUILDDIR=$T/arch/b PKGDEST=$T/arch SRCDEST=$T/arch PKGEXT=.pkg.tar.zst PACKAGER=$ARCH_PACKAGER \
    makepkg --nodeps --noconfirm --force >&2)
  mkdir -p "$out"
  cp "$T/arch/$ARCH_PACKAGE-$ver-1-any.pkg.tar.zst" "$out/"
  echo "$out/$ARCH_PACKAGE-$ver-1-any.pkg.tar.zst"
}

nix_package() { # <root> <version> <out>
  local root=$1 version=$2 out=$3 ver f top
  ver=${version%%+*}   # the flavour is always overlay here: the date alone, like the other Nix flakes' versions
  mkdir -p "$out"
  rm -rf "$out/flake" "$out/$NIX_PACKAGE.tar.gz"
  mkdir -p "$out/flake"
  for f in flake.nix flake.lock package.nix module.nix; do
    git show "HEAD:packaging/nix/$f" >"$out/flake/$f" || die "HEAD has no packaging/nix/$f"
  done
  # the staged tree as one plain tar member: the profiles are links, and the signing box's nix-publish takes only
  # plain files and directories in a flake tarball (it reads every file's bytes, so a tar is still scanned)
  tar -C "$(dirname "$root")" --owner=0 --group=0 --numeric-owner --mtime=@0 --sort=name \
    -cf "$out/flake/root.tar" "$(basename "$root")"
  printf '"%s"\n' "$ver" >"$out/flake/version.nix"
  top=$NIX_PACKAGE-$ver
  tar -C "$out" --transform="s|^flake|$top|" --owner=0 --group=0 --numeric-owner --mtime=@0 --sort=name \
    -czf "$out/$NIX_PACKAGE.tar.gz" flake
  echo "$out/$NIX_PACKAGE.tar.gz"
}

main() {
  local format="" flavour=overlay version="" out=""
  while (($#)); do
    case $1 in
      --format) format=${2:?}; shift 2 ;;
      --flavour) flavour=${2:?}; shift 2 ;;
      --version) version=${2:?}; shift 2 ;;
      --out) out=${2:?}; shift 2 ;;
      --dist) DIST=${2:?}; shift 2 ;;
      --release) RELEASE=${2:?}; shift 2 ;;
      *) die "usage: build-overlay.sh --format deb|rpm|arch|nix [--flavour overlay|overlay-legacy] [--version YYYY.MM.DD] [--dist .tw|.lp<NNN>] [--release N] [--out DIR]" ;;
    esac
  done
  [[ -z $DIST || ($format == rpm && $DIST =~ ^\.(tw|lp[0-9]{3})$) ]] || die "--dist is .tw or .lp<NNN>, for --format rpm"
  [[ $RELEASE =~ ^[1-9][0-9]{0,2}$ ]] || die "--release $RELEASE is not 1-999"
  [[ $RELEASE == 1 || $format == rpm ]] || die "--release is for --format rpm"
  case $format in deb | rpm | arch | nix) ;; *) die "--format deb, rpm, arch or nix" ;; esac
  [[ $format != nix || $flavour == overlay ]] || die "--format nix is the overlay flavour (NixOS's alsa-ucm-conf is >= 1.2.11)"
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
  # every staged path is a regular file, a link or a directory (whether a link resolves is the install review's)
  local bad
  bad=$(cd "$T/root" && find . ! -type f ! -type l ! -type d | head -1)
  [[ -z $bad ]] || die "staged $bad is not a file or a link"
  find "$T/root" -type f -exec chmod 0644 {} +
  find "$T/root" -type d -exec chmod 0755 {} +
  local name
  case $format in deb) name=$DEB_PACKAGE ;; rpm) name=$RPM_PACKAGE ;; arch) name=$ARCH_PACKAGE ;; nix) name=$NIX_PACKAGE ;; esac
  log "$name $version ($flavour, $n files) from $(git rev-parse --short=12 HEAD)"
  "${format}_package" "$T/root" "$version" "$out"
}

main "$@"
