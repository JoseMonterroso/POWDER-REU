#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/webapp-done ]; then
    exit 0
fi

cd $OURDIR

if [ ! -e $OURDIR/demo-capsule ]; then
    git clone https://gitlab.flux.utah.edu/safeedge/demo-capsule.git
    cd demo-capsule
    sed -i -e 's|url = git@gitlab.flux.utah.edu:|url = https://gitlab.flux.utah.edu/|' .gitmodules
    git submodule update --init --recursive
    cd ..
fi

cd $OURDIR/demo-capsule/segment-routing-webapp
./replace_sdn_controller_name.sh localhost
python3 -m http.server 2>&1 > $OURDIR/webapp.log &

touch $OURDIR/webapp-done

exit 0
