#!/bin/bash

cd $(readlink -f $(dirname ${BASH_SOURCE[0]}))

TARGET=$1

if [ -z "$TARGET" ]; then
	echo $0 TARGET
	exit 1
fi

. build.sh

scp ${package}_*.deb $TARGET:
ssh "$TARGET" sudo dpkg -i ${package}_*.deb
