#!/bin/bash

dateymd=$(date +%Y.%m.%d)
commit=$(git rev-parse HEAD)
dateutc=$(date -Ru)
cat <<EOF > debian/changelog
libretech-alsa-ucm-conf ($dateymd) linux; urgency=medium

  * $commit

 -- Da Xue <da@libre.computer>  $dateutc
EOF
dpkg-buildpackage -uc --no-sign --build=all
