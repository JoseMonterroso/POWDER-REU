#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/orchestrator-done ]; then
    exit 0
fi

cd $OURDIR

MS=
if [ -n "$MGMTLAN" ]; then
    MS="--mgmt-network=$MGMTLAN"
fi

if [ ! -e $OURDIR/netinfo.json ]; then
    err=1
    while [ ! $err -eq 0 ]; do
	$SRC/manifest-to-netjson.py $MS --no-links $OURDIR/manifests.0.xml \
            > $OURDIR/netinfo.json
	err=$?
	if [ ! $err -eq 0 ]; then
	    echo "ERROR: failed to convert manifest to netjson; assuming some interfaces are not yet present; sleeping and trying again..."
	    sleep 8
	fi
    done
fi

if [ ! -e $OURDIR/demo-capsule ]; then
    git clone https://gitlab.flux.utah.edu/safeedge/demo-capsule.git
    cd demo-capsule
    sed -i -e 's|url = git@gitlab.flux.utah.edu:|url = https://gitlab.flux.utah.edu/|' .gitmodules
    git submodule update --init --recursive
    cd ..
fi

maybe_install_packages virtualenv python-pip python3

cd demo-capsule/segment-routing-orchestrator
virtualenv -p /usr/bin/python3 env
. env/bin/activate
pip install -r requirements.txt

./orchestrator.py \
    -d --netgraph-file=$OURDIR/netinfo.json \
    --username=root --no-sniffer --no-ipv6-assign
deactivate

touch $OURDIR/orchestrator-done

exit 0
