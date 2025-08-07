#!/bin/bash

set -x

cd $(readlink -f $(dirname ${BASH_SOURCE[0]}))

package=libretech-alsa-ucm-conf
dateymd=$(date -u +%Y.%m.%d)
commit=$(git rev-parse HEAD)
dateutc=$(date -Ru)

cat <<EOF > debian/changelog
$package ($dateymd) linux; urgency=medium

  * $commit

 -- Da Xue <da@libre.computer>  $dateutc
EOF

dpkg-buildpackage -uc --no-sign --build=all

mv ../${package}_* .
